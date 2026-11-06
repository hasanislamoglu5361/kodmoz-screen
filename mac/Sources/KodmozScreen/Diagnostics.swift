import Foundation
import CoreGraphics
import AppKit

enum Diagnostics {
    static func run() -> Int32 {
        // AppKit'i ve pencere sunucusu bağlantısını başlat; sanal ekranın
        // modları ancak çalışan bir runloop ile uygulanıyor.
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.finishLaunching()
        print("Kodmoz Screen \(AppInfo.version) · tanılama")
        print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("Mimari: \(AppInfo.architecture)")
        print("")

        print("Mevcut ekranlar:")
        for screen in NSScreen.screens {
            printScreen(screen)
        }
        print("")

        let preset = Preferences.shared.resolution
        print("Sanal ekran deneniyor: \(preset.title) (\(preset.hiDPI ? "Retina" : "1×"))")
        guard let display = VirtualDisplay(preset: preset) else {
            print("SONUÇ: CGVirtualDisplay oluşturulamadı. Aynalama modu kullanılabilir.")
            return 1
        }
        let online = display.waitUntilOnline()
        // Pencere sunucusunun modu uygulaması için runloop'u çalıştır.
        pumpRunLoop(seconds: 1.5)
        print("  displayID: \(display.displayID)")
        print("  çevrimiçi: \(online)")
        print("  aktif: \(CGDisplayIsActive(display.displayID) != 0) · uyku: \(CGDisplayIsAsleep(display.displayID) != 0)")
        print("  CGDisplayPixels: \(Int(display.pixelSize.width))×\(Int(display.pixelSize.height))")
        print("  nokta:  \(Int(display.pointSize.width))×\(Int(display.pointSize.height))")
        print("  konum:  \(Int(display.bounds.origin.x)),\(Int(display.bounds.origin.y))")
        if let mode = CGDisplayCopyDisplayMode(display.displayID) {
            print("  mod:    \(mode.width)×\(mode.height) pt · \(mode.pixelWidth)×\(mode.pixelHeight) px · \(mode.refreshRate) Hz")
        }
        if let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID }) {
            print("  NSScreen:")
            printScreen(screen, prefix: "    ")
        } else {
            print("  NSScreen: bulunamadı")
        }
        print("")

        if let modes = CGDisplayCopyAllDisplayModes(display.displayID, nil) as? [CGDisplayMode] {
            print("Ekran modları (\(modes.count)):")
            for mode in modes {
                print("  - \(mode.width)×\(mode.height) pt · \(mode.pixelWidth)×\(mode.pixelHeight) px · \(mode.refreshRate) Hz · ioFlags=\(mode.ioFlags)")
            }
        }

        print("")
        print("3 saniye sonra sanal ekran kaldırılacak…")
        pumpRunLoop(seconds: 3)
        return 0
    }

    private static func pumpRunLoop(seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }
}

private func printScreen(_ screen: NSScreen, prefix: String = "  - ") {
    let id = screen.displayID
    var modeText = "mod yok"
    if let mode = CGDisplayCopyDisplayMode(id) {
        modeText = "\(mode.width)×\(mode.height) pt · \(mode.pixelWidth)×\(mode.pixelHeight) px · \(mode.refreshRate) Hz"
    }
    print("\(prefix)\(screen.localizedName) · id=\(id) · frame \(Int(screen.frame.width))×\(Int(screen.frame.height)) · scale @\(Int(screen.backingScaleFactor))× · \(modeText)")
}

extension NSScreen {
    /// NSScreen'in CGDirectDisplayID'si.
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "bilinmiyor"
        #endif
    }

    static let repositoryURL = "https://github.com/hasanislamoglu5361/kodmoz-screen"
}
