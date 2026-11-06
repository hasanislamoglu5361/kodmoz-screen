import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var onClose: () -> Void

    @State private var resolution: ResolutionPreset
    @State private var fps: Int
    @State private var bitrate: Int
    @State private var port: String
    @State private var showCursor: Bool
    @State private var inputEnabled: Bool
    @State private var naturalScroll: Bool
    @State private var requireCode: Bool
    @State private var mirrorMode: Bool
    @State private var serverEnabled: Bool
    @State private var portError: String?

    init(model: AppModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        let prefs = Preferences.shared
        _resolution = State(initialValue: prefs.resolution)
        _fps = State(initialValue: prefs.fps)
        _bitrate = State(initialValue: prefs.bitrateMbps)
        _port = State(initialValue: String(prefs.port))
        _showCursor = State(initialValue: prefs.showCursor)
        _inputEnabled = State(initialValue: prefs.inputEnabled)
        _naturalScroll = State(initialValue: prefs.naturalScroll)
        _requireCode = State(initialValue: prefs.requireCode)
        _mirrorMode = State(initialValue: prefs.mirrorMode)
        _serverEnabled = State(initialValue: prefs.serverEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Ayarlar")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Text("Kodmoz Screen v\(model.version)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("EKRAN") {
                        row("Çözünürlük") {
                            Picker("", selection: $resolution) {
                                ForEach(ResolutionPreset.allCases) { preset in
                                    Text("\(preset.title) — \(preset.hiDPI ? "Retina" : "1×")")
                                        .tag(preset)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 230)
                        }

                        row("Kare hızı") {
                            Picker("", selection: $fps) {
                                Text("30 fps").tag(30)
                                Text("60 fps").tag(60)
                            }
                            .labelsHidden()
                            .frame(width: 130)
                        }

                        row("Bit hızı") {
                            Picker("", selection: $bitrate) {
                                Text("Otomatik").tag(0)
                                Text("8 Mbps").tag(8)
                                Text("12 Mbps").tag(12)
                                Text("20 Mbps").tag(20)
                                Text("30 Mbps").tag(30)
                                Text("40 Mbps").tag(40)
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }

                        Toggle("İmleci yayında göster", isOn: $showCursor)
                        Toggle("Ana ekranı aynala (ikinci ekran oluşturma)", isOn: $mirrorMode)
                    }

                    section("BAĞLANTI") {
                        row("Port") {
                            TextField("", text: $port)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                                .multilineTextAlignment(.trailing)
                        }
                        if let portError {
                            Text(portError)
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                        }
                        Toggle("Eşleşme kodu iste", isOn: $requireCode)
                        Toggle("Sunucu açık", isOn: $serverEnabled)
                    }

                    section("GİRİŞ") {
                        Toggle("Dokunmatik fare ve klavye", isOn: $inputEnabled)
                        Toggle("Doğal kaydırma yönü", isOn: $naturalScroll)
                            .disabled(!inputEnabled)
                        if inputEnabled && !model.accessibilityPermission {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Erişilebilirlik izni yok; dokunmatik kontrol çalışmaz.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("İzin İste") { model.requestAccessibility() }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                    }

                    if !model.screenPermission {
                        section("İZİNLER") {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Ekran Kaydı izni yok. Görüntü aktarılamaz.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("İzin İste") { model.requestScreenPermission() }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                    }
                }
                .padding(22)
            }

            Divider()

            HStack {
                Button("Varsayılanlar") {
                    let prefs = Preferences.shared
                    resolution = .default
                    fps = 60
                    bitrate = 20
                    port = "9280"
                    showCursor = true
                    inputEnabled = true
                    naturalScroll = true
                    requireCode = prefs.requireCode
                    mirrorMode = false
                    serverEnabled = true
                    portError = nil
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Spacer()

                Button("Kapat") { onClose() }
                    .keyboardShortcut(.cancelAction)

                Button("Uygula") { apply() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
        .frame(width: 470)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func apply() {
        guard let value = Int(port), (1024...65535).contains(value) else {
            portError = "Port 1024–65535 arasında olmalı."
            return
        }
        portError = nil
        model.applySettings(
            resolution: resolution,
            fps: fps,
            bitrate: bitrate,
            port: value,
            showCursor: showCursor,
            inputEnabled: inputEnabled,
            naturalScroll: naturalScroll,
            requireCode: requireCode,
            mirrorMode: mirrorMode,
            serverEnabled: serverEnabled
        )
        onClose()
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
            Spacer()
            content()
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.1)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07))
            )
        }
    }
}
