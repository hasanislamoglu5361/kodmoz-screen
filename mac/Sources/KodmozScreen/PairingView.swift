import SwiftUI
import AppKit

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07))
            )
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

struct PairingView: View {
    @ObservedObject var model: AppModel
    var onOpenSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                statusCard
                if let error = model.errorText {
                    errorCard(error)
                }
                connectionCard
                if !model.screenPermission {
                    permissionCard(
                        title: "Ekran Kaydı izni gerekli",
                        message: "Sanal ekranı yakalamak için Sistem Ayarları > Gizlilik ve Güvenlik > Ekran Kaydı bölümünde Kodmoz Screen'i açın. İzin verdikten sonra uygulamayı yeniden başlatın.",
                        primary: "İzin İste",
                        secondary: "Ayarları Aç",
                        action: model.requestScreenPermission,
                        openSettings: model.openScreenRecordingSettings
                    )
                }
                if model.inputEnabled && !model.accessibilityPermission {
                    permissionCard(
                        title: "Dokunmatik kontrol için izin",
                        message: "Tabletten fare ve klavye kontrolü için Erişilebilirlik izni gerekir. İzin vermezseniz görüntü gelir, dokunmatik çalışmaz.",
                        primary: "İzin İste",
                        secondary: "Ayarları Aç",
                        action: model.requestAccessibility,
                        openSettings: model.openAccessibilitySettings
                    )
                }
                usbCard
                footer
            }
            .padding(22)
        }
        .frame(width: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Başlık

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.36, green: 0.32, blue: 0.86),
                                 Color(red: 0.55, green: 0.33, blue: 0.92)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 52, height: 52)
                .overlay(
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Kodmoz Screen")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Tabletini Mac'in için ikinci ekran yap")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("v\(model.version)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Durum

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                    .shadow(color: statusColor.opacity(0.6), radius: 4)
                Text(model.statusText)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if model.isConnected {
                    Text("CANLI")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.green.opacity(0.18)))
                        .foregroundColor(.green)
                }
            }

            HStack(spacing: 18) {
                stat("\(Int(model.fps.rounded())) fps", icon: "speedometer")
                stat(String(format: "%.1f Mbps", model.mbps), icon: "waveform.path.ecg")
                if model.isConnected {
                    stat(model.resolutionText, icon: "rectangle.inset.filled")
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "display")
                    .font(.system(size: 11))
                Text(model.resolutionText)
                Text("·")
                Text(model.logicalSizeText)
                Text("·")
                Text(model.backendText)
                if model.mirrorMode {
                    Text("·")
                    Text("aynalama")
                }
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
        .card()
    }

    private func stat(_ text: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
        .foregroundColor(.secondary)
    }

    private var statusColor: Color {
        if model.errorText != nil { return .orange }
        if model.isConnected { return .green }
        if model.isRunning { return Color(red: 0.3, green: 0.55, blue: 1) }
        return .secondary
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
    }

    // MARK: - Bağlantı

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TABLETTEN BAĞLAN")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Ağ adresi")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    if let first = model.addresses.first {
                        Button {
                            model.copy(first)
                        } label: {
                            Label("Kopyala", systemImage: "doc.on.doc")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    }
                }

                if model.addresses.isEmpty {
                    Text("Ağ bağlantısı bulunamadı")
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundColor(.secondary)
                } else {
                    Text(model.addresses[0])
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                    if model.addresses.count > 1 {
                        Text(model.addresses.dropFirst().joined(separator: "  ·  "))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Divider()

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Eşleşme kodu")
                        .font(.system(size: 12, weight: .medium))
                    Text(model.requireCode ? "Tablette ilk bağlantıda sorulur" : "Kod isteme kapalı")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(model.requireCode ? model.pairingCode : "—")
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .tracking(model.requireCode ? 6 : 0)
                    .textSelection(.enabled)
                if model.requireCode {
                    Button {
                        model.regenerateCode()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .help("Yeni kod üret")
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                instruction(1, "Tablette Kodmoz Screen uygulamasını açın.")
                instruction(2, "Listeden “Kodmoz Screen — \(Host.current().localizedName ?? "Mac")” seçin.")
                instruction(3, "Ağ adresini ve kodu girin; ekran otomatik açılır.")
            }
        }
        .card()
    }

    private func instruction(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - İzin

    private func permissionCard(
        title: String,
        message: String,
        primary: String,
        secondary: String,
        action: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundColor(.orange)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(primary, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button(secondary, action: openSettings)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
    }

    // MARK: - USB

    private var usbCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "cable.connector")
                    .foregroundColor(.secondary)
                Text("USB ile bağlanmak")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    model.copy("adb reverse tcp:\(String(Preferences.shared.port)) tcp:\(String(Preferences.shared.port))")
                } label: {
                    Label("Kopyala", systemImage: "doc.on.doc")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
            Text("adb reverse tcp:\(String(Preferences.shared.port)) tcp:\(String(Preferences.shared.port))")
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            Text("Mac'te bu komutu çalıştırın (USB hata ayıklama açık olmalı), tablette 127.0.0.1 adresini kullanın.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    // MARK: - Alt çubuk

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                onOpenSettings()
            } label: {
                Label("Ayarlar", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)

            Spacer()

            if model.isRunning {
                Button {
                    model.stop()
                } label: {
                    Label("Duraklat", systemImage: "pause.fill")
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    model.start()
                } label: {
                    Label("Başlat", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                model.restart()
            } label: {
                Label("Yenile", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .help("Sanal ekranı ve yayını yeniden başlat")
        }
    }
}
