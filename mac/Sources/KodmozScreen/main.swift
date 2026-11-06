import Foundation
import AppKit

// Kodmoz Screen — tabletinizi Mac için ikinci ekran yapan menü çubuğu uygulaması.

let arguments = CommandLine.arguments

func argumentValue(after flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag),
          arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

if arguments.contains("--make-icon") {
    let directory = URL(fileURLWithPath: argumentValue(after: "--make-icon") ?? "build/icon")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    exit(IconRenderer.renderIconSet(to: directory) ? 0 : 1)
}

if arguments.contains("--version") {
    print("Kodmoz Screen \(AppInfo.version) (\(AppInfo.build))")
    exit(0)
}

if arguments.contains("--diagnose") {
    exit(Diagnostics.run())
}

if arguments.contains("--test-pattern") {
    // Ekran kaydı izni olmadan sunucu + kodlayıcı + protokol hattını test eder.
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let pipeline = ScreenPipeline()
    pipeline.onError = { message in
        print("HATA: \(message)")
        fflush(stdout)
    }
    pipeline.onStateChange = {
        print("DURUM: \(pipeline.server.status.text)")
        fflush(stdout)
    }
    pipeline.onBackendChange = { backend in
        print("YAKALAMA: \(backend.rawValue)")
        fflush(stdout)
    }
    pipeline.start(testPattern: true)
    print("READY port=\(Preferences.shared.port) code=\(Preferences.shared.pairingCode)")
    print("Tabletten bu Mac'e bağlanın; çıkmak için Ctrl+C.")
    fflush(stdout)
    app.run()
    exit(0)
}

// Geliştirme yardımcısı: sanal ekranın gerçekten pencere sunucusuna
// kaydolduğunu ve mod listesini gösterir.
if arguments.contains("--hold") {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let window = NSWindow(
        contentRect: NSRect(x: 120, y: 120, width: 420, height: 180),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    window.title = "Kodmoz Screen Test"
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)

    let preset = argumentValue(after: "--hold")
        .flatMap(ResolutionPreset.init(rawValue:)) ?? Preferences.shared.resolution
    var display: VirtualDisplay? = VirtualDisplay(preset: preset)
    print("display=\(display?.displayID ?? 0) pid=\(ProcessInfo.processInfo.processIdentifier)")
    var ticks = 0
    Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
        ticks += 1
        let screens = NSScreen.screens.map {
            "\($0.displayID):\(Int($0.frame.width))x\(Int($0.frame.height))@\(Int($0.backingScaleFactor))x"
        }
        print("tick \(ticks) screens=\(screens)")
        if let id = display?.displayID,
           let mode = CGDisplayCopyDisplayMode(id) {
            print("  mode=\(mode.width)x\(mode.height) pt · \(mode.pixelWidth)x\(mode.pixelHeight) px · \(mode.refreshRate) Hz")
        }
        if ticks >= 8 {
            timer.invalidate()
            display = nil
            NSApp.terminate(nil)
        }
    }
    app.run()
    _ = display
    exit(0)
}

// Normal uygulama.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
