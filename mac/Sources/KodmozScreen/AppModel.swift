import Foundation
import SwiftUI
import AppKit

/// Veri akışından bağımsız ağ adresleri.
enum NetworkInfo {
    static func localIPv4Addresses() -> [String] {
        var addresses: [String] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }

        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }
            guard let address = entry.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(address.pointee.sa_len)
            let result = getnameinfo(
                address,
                length,
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if result == 0 {
                let ip = String(cString: host)
                if !ip.isEmpty { addresses.append(ip) }
            }
        }
        return Array(Set(addresses)).sorted()
    }
}

final class AppModel: ObservableObject {
    @Published var statusText = "Başlatılıyor…"
    @Published var isConnected = false
    @Published var isRunning = false
    @Published var isStarting = false
    @Published var fps: Double = 0
    @Published var mbps: Double = 0
    @Published var errorText: String?
    @Published var screenPermission = ScreenPipeline.hasScreenRecordingPermission
    @Published var accessibilityPermission = InputInjector.isAccessibilityTrusted
    @Published var resolutionText = "—"
    @Published var logicalSizeText = "—"
    @Published var backendText = "—"
    @Published var addresses: [String] = []
    @Published var pairingCode = Preferences.shared.pairingCode
    @Published var requireCode = Preferences.shared.requireCode
    @Published var serverEnabled = Preferences.shared.serverEnabled
    @Published var inputEnabled = Preferences.shared.inputEnabled
    @Published var mirrorMode = Preferences.shared.mirrorMode
    @Published var version = AppInfo.version

    let pipeline: ScreenPipeline
    private let prefs = Preferences.shared
    var onChange: (() -> Void)?

    init(pipeline: ScreenPipeline) {
        self.pipeline = pipeline
        wirePipeline()
        refresh()
    }

    private func wirePipeline() {
        pipeline.onStateChange = { [weak self] in
            self?.onMain { $0.refresh() }
        }
        pipeline.onStats = { [weak self] fps, mbps in
            self?.onMain {
                $0.fps = fps
                $0.mbps = mbps
                $0.onChange?()
            }
        }
        pipeline.onError = { [weak self] message in
            self?.onMain {
                $0.errorText = message
                $0.refreshPermissions()
                $0.onChange?()
            }
        }
        pipeline.onBackendChange = { [weak self] backend in
            self?.onMain {
                $0.backendText = backend.rawValue
                $0.onChange?()
            }
        }
    }

    private func onMain(_ body: @escaping (AppModel) -> Void) {
        if Thread.isMainThread {
            body(self)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                body(self)
            }
        }
    }

    func refresh() {
        statusText = pipeline.server.status.text
        isConnected = pipeline.server.isStreaming
        isRunning = pipeline.isActive
        resolutionText = pipeline.resolutionText
        logicalSizeText = pipeline.logicalSizeText
        mirrorMode = prefs.mirrorMode || pipeline.isMirroring
        backendText = pipeline.captureBackend?.rawValue ?? "—"
        pairingCode = prefs.pairingCode
        requireCode = prefs.requireCode
        serverEnabled = prefs.serverEnabled
        inputEnabled = prefs.inputEnabled
        addresses = NetworkInfo.localIPv4Addresses().map { "\($0):\(prefs.port)" }
        refreshPermissions()
        onChange?()
    }

    func refreshPermissions() {
        screenPermission = ScreenPipeline.hasScreenRecordingPermission
        accessibilityPermission = InputInjector.isAccessibilityTrusted
    }

    // MARK: - Komutlar

    func start() {
        guard !pipeline.isActive else { return }
        prefs.serverEnabled = true
        isStarting = true
        errorText = nil
        pipeline.start()
        refresh()
    }

    func stop() {
        pipeline.stop()
        isStarting = false
        refresh()
    }

    func toggleRunning() {
        if pipeline.isActive {
            stop()
        } else {
            start()
        }
    }

    func restart() {
        errorText = nil
        pipeline.restart()
        refresh()
    }

    func regenerateCode() {
        pairingCode = prefs.regeneratePairingCode()
        pipeline.server.setRequiredCode(prefs.requireCode ? pairingCode : nil)
        onChange?()
    }

    func copy(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    func applySettings(
        resolution: ResolutionPreset,
        fps: Int,
        bitrate: Int,
        port: Int,
        showCursor: Bool,
        inputEnabled: Bool,
        naturalScroll: Bool,
        requireCode: Bool,
        mirrorMode: Bool,
        serverEnabled: Bool
    ) {
        prefs.resolution = resolution
        prefs.fps = fps
        prefs.bitrateMbps = bitrate
        prefs.port = port
        prefs.showCursor = showCursor
        prefs.inputEnabled = inputEnabled
        prefs.naturalScroll = naturalScroll
        prefs.requireCode = requireCode
        prefs.mirrorMode = mirrorMode
        prefs.serverEnabled = serverEnabled

        pipeline.injector.enabled = inputEnabled
        pipeline.injector.naturalScroll = naturalScroll
        pipeline.server.setRequiredCode(requireCode ? prefs.pairingCode : nil)

        if serverEnabled {
            pipeline.restart()
        } else {
            pipeline.stop()
        }
        refresh()
    }

    func requestScreenPermission() {
        ScreenPipeline.requestScreenRecordingPermission()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.refreshPermissions()
        }
    }

    func requestAccessibility() {
        InputInjector.requestAccessibility()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.refreshPermissions()
        }
    }

    func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openRepository() {
        open(AppInfo.repositoryURL)
    }

    private func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
