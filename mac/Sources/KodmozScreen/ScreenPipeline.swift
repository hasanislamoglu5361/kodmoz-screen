import Foundation
import AppKit
import CoreGraphics

/// Sanal ekran → yakalama → H.264 → TCP hattının tamamını yönetir.
final class ScreenPipeline {
    let server = StreamServer()
    let injector = InputInjector()

    private let prefs = Preferences.shared
    private(set) var virtualDisplay: VirtualDisplay?
    private var capture: ScreenCaptureEngine?
    private var testPattern: TestPatternSource?
    private var encoder: H264Encoder?
    private var displayID: CGDirectDisplayID = 0
    private var pixelWidth = 0
    private var pixelHeight = 0
    private var scale = 1
    private var isRunning = false
    private var isStarting = false
    private var testPatternMode = false
    private var mirrorMode = false
    private let stateLock = NSLock()
    private var encodingEnabled = false

    var onStateChange: (() -> Void)?
    var onError: ((String) -> Void)?
    var onStats: ((_ fps: Double, _ mbps: Double) -> Void)?
    var onBackendChange: ((ScreenCaptureEngine.Backend) -> Void)?

    var isActive: Bool { isRunning }
    var isUsingTestPattern: Bool { testPatternMode }
    var isMirroring: Bool { mirrorMode }

    var resolutionText: String {
        guard pixelWidth > 0, pixelHeight > 0 else { return "—" }
        return "\(pixelWidth) × \(pixelHeight) px"
    }

    var logicalSizeText: String {
        guard pixelWidth > 0 else { return "—" }
        let w = pixelWidth / max(1, scale)
        let h = pixelHeight / max(1, scale)
        return scale > 1 ? "\(w) × \(h) nokta @\(scale)×" : "\(w) × \(h) nokta"
    }

    var captureBackend: ScreenCaptureEngine.Backend? {
        if testPatternMode { return .testPattern }
        return capture?.backend
    }

    var virtualDisplaySummary: String {
        virtualDisplay?.summary ?? (mirrorMode ? "Ana ekran aynalanıyor" : "—")
    }

    // MARK: - Başlatma

    func start(testPattern: Bool = false) {
        guard !isRunning, !isStarting else { return }
        isStarting = true
        testPatternMode = testPattern
        mirrorMode = false

        guard prefs.serverEnabled || testPattern else {
            isStarting = false
            return
        }

        if testPattern {
            pixelWidth = prefs.resolution.width
            pixelHeight = prefs.resolution.height
            scale = prefs.resolution.hiDPI ? 2 : 1
            beginCaptureAndServer()
            return
        }

        if prefs.mirrorMode {
            beginMirror(showError: false)
            return
        }

        guard let display = VirtualDisplay(preset: prefs.resolution) else {
            onError?("Sanal ekran oluşturulamadı. Ana ekran aynalanıyor.")
            beginMirror(showError: false)
            return
        }
        virtualDisplay = display
        displayID = display.displayID
        let preset = prefs.resolution

        // Pencere sunucusunun ekranı kaydetmesi ve mod seçimini uygulaması
        // için kısa bir gecikme gerekiyor.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.isStarting else { return }
            let selected = display.selectMode(
                pixelWidth: preset.width,
                pixelHeight: preset.height,
                hiDPI: preset.hiDPI
            )
            NSLog("[KodmozScreen] mod seçimi %@: %dx%d (hiDPI %@)",
                  selected ? "başarılı" : "başarısız",
                  preset.width, preset.height, preset.hiDPI ? "açık" : "kapalı")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, self.isStarting else { return }
                let size = self.virtualDisplay?.pixelSize ?? CGSize(width: preset.width, height: preset.height)
                self.pixelWidth = Int(size.width)
                self.pixelHeight = Int(size.height)
                self.scale = max(1, Int(self.virtualDisplay?.scaleFactor ?? 1))
                if self.pixelWidth <= 0 || self.pixelHeight <= 0 {
                    self.pixelWidth = preset.width
                    self.pixelHeight = preset.height
                }
                self.beginCaptureAndServer()
            }
        }
    }

    private func beginMirror(showError: Bool) {
        mirrorMode = true
        let mainID = NSScreen.main?.displayID ?? CGMainDisplayID()
        displayID = mainID
        if let mode = CGDisplayCopyDisplayMode(mainID) {
            pixelWidth = mode.pixelWidth
            pixelHeight = mode.pixelHeight
        }
        if pixelWidth <= 0 || pixelHeight <= 0 {
            let frame = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
            let factor = NSScreen.main?.backingScaleFactor ?? 2
            pixelWidth = Int(frame.width * factor)
            pixelHeight = Int(frame.height * factor)
        }
        scale = max(1, Int(NSScreen.main?.backingScaleFactor ?? 1))
        beginCaptureAndServer()
    }

    private func beginCaptureAndServer() {
        guard isStarting else { return }
        isStarting = false
        isRunning = true

        if !testPatternMode && !ScreenPipeline.hasScreenRecordingPermission {
            onError?("Ekran Kaydı izni yok. Sistem Ayarları > Gizlilik ve Güvenlik > Ekran Kaydı bölümünden Kodmoz Screen'e izin verin.")
        }

        let fps = prefs.fps
        let bitrate = prefs.resolvedBitrate
        let encoder = H264Encoder(configuration: .init(
            width: pixelWidth,
            height: pixelHeight,
            fps: fps,
            bitrate: bitrate
        ))
        self.encoder = encoder
        encoder.onFrame = { [weak self] payload, keyframe, sps, pps in
            self?.server.sendVideo(payload, keyframe: keyframe, sps: sps, pps: pps)
        }
        encoder.onError = { [weak self] message in
            self?.onError?(message)
        }

        if testPatternMode {
            let pattern = TestPatternSource()
            pattern.onFrame = { [weak self] pixelBuffer, time in
                guard let self, self.shouldEncode else { return }
                self.encoder?.encode(pixelBuffer: pixelBuffer, presentationTime: time)
            }
            pattern.start(width: pixelWidth, height: pixelHeight, fps: fps)
            testPattern = pattern
        } else {
            let capture = ScreenCaptureEngine()
            capture.onBackendChange = { [weak self] backend in
                self?.onBackendChange?(backend)
                self?.onStateChange?()
            }
            capture.onFrame = { [weak self] pixelBuffer, time, _ in
                guard let self, self.shouldEncode else { return }
                self.encoder?.encode(pixelBuffer: pixelBuffer, presentationTime: time)
            }
            capture.onError = { [weak self] message in
                self?.onError?(message)
            }
            capture.start(
                displayID: displayID,
                width: pixelWidth,
                height: pixelHeight,
                fps: fps,
                showCursor: prefs.showCursor
            )
            self.capture = capture
        }

        server.displayInfoProvider = { [weak self] in
            guard let self else {
                return StreamServer.DisplayInfo(
                    width: 1280, height: 800, fps: 60,
                    bitrate: 12_000_000, scale: 2, name: "Kodmoz Screen"
                )
            }
            return StreamServer.DisplayInfo(
                width: self.pixelWidth,
                height: self.pixelHeight,
                fps: fps,
                bitrate: bitrate,
                scale: self.scale,
                name: self.testPatternMode ? "Kodmoz Screen (Test)" : "Kodmoz Screen"
            )
        }
        server.onInput = { [weak self] event in
            self?.injector.handle(event)
        }
        server.onKeyframeNeeded = { [weak self] in
            guard let self else { return }
            self.setEncodingEnabled(true)
            self.encoder?.forceKeyframe()
            self.capture?.requestStillFrame()
        }
        server.onStatusChange = { [weak self] status in
            guard let self else { return }
            switch status {
            case .clientConnecting, .streaming:
                self.setEncodingEnabled(true)
                self.encoder?.forceKeyframe()
                self.capture?.requestStillFrame()
            case .listening, .stopped, .failed:
                self.setEncodingEnabled(false)
            }
            self.onStateChange?()
        }
        server.onStats = { [weak self] fps, mbps in
            self?.onStats?(fps, mbps)
        }

        injector.boundsProvider = { [weak self] in
            guard let self, let display = self.virtualDisplay else {
                return CGDisplayBounds(CGMainDisplayID())
            }
            return display.bounds
        }
        injector.naturalScroll = prefs.naturalScroll
        injector.enabled = prefs.inputEnabled

        let serviceName = "Kodmoz Screen — \(Host.current().localizedName ?? "Mac")"
        server.start(
            port: prefs.port,
            serviceName: String(serviceName.prefix(60)),
            requiredCode: prefs.requireCode ? prefs.pairingCode : nil
        )

        onStateChange?()
    }

    // MARK: - Durdurma

    func stop() {
        isStarting = false
        isRunning = false
        setEncodingEnabled(false)

        capture?.stop()
        capture = nil
        testPattern?.stop()
        testPattern = nil
        encoder?.invalidate()
        encoder = nil
        server.stop()

        virtualDisplay = nil
        displayID = 0
        mirrorMode = false
        pixelWidth = 0
        pixelHeight = 0
        scale = 1
        onStateChange?()
    }

    func restart(testPattern: Bool = false) {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.start(testPattern: testPattern)
        }
    }

    func restartInPlace() {
        restart()
    }

    func forceKeyframe() {
        encoder?.forceKeyframe()
    }

    func updateBitrate() {
        encoder?.updateBitrate(prefs.resolvedBitrate)
    }

    /// Kullanıcı Sistem Ayarları'ndan çözünürlük değiştirdiyse hattı yenile.
    func handleScreenParametersChanged() {
        guard isRunning, !testPatternMode, !mirrorMode, let display = virtualDisplay else { return }
        let size = display.pixelSize
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0 else { return }
        guard width != pixelWidth || height != pixelHeight else { return }
        NSLog("[KodmozScreen] ekran boyutu değişti: %dx%d → %dx%d",
              pixelWidth, pixelHeight, width, height)
        restart()
    }

    // MARK: - İzinler

    static var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    // MARK: - Kodlama kilidi

    private var shouldEncode: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return encodingEnabled && isRunning
    }

    private func setEncodingEnabled(_ enabled: Bool) {
        stateLock.lock()
        encodingEnabled = enabled
        stateLock.unlock()
    }
}
