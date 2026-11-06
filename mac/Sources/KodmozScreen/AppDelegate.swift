import Foundation
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let pipeline = ScreenPipeline()
    private lazy var model = AppModel(pipeline: pipeline)

    private var statusItem: NSStatusItem?
    private var pairingWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var displayChangeWorkItem: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()
        setupStatusItem()

        model.onChange = { [weak self] in
            self?.refreshStatusItem()
        }
        refreshStatusItem()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        if Preferences.shared.serverEnabled {
            model.start()
        }

        if !Preferences.shared.didShowWelcome {
            Preferences.shared.didShowWelcome = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.showPairing()
            }
        }

        // Ekran kaydı izni yoksa sistem istemini bir kez göster.
        if !ScreenPipeline.hasScreenRecordingPermission {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                ScreenPipeline.requestScreenRecordingPermission()
                self?.model.refreshPermissions()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pipeline.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Menü çubuğu

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.on.rectangle",
                accessibilityDescription: "Kodmoz Screen"
            )
            button.image?.isTemplate = true
            button.toolTip = "Kodmoz Screen"
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        buildMenu(menu)
        statusItem = item
    }

    private func buildMenu(_ menu: NSMenu) {
        let status = NSMenuItem(title: "Kodmoz Screen", action: nil, keyEquivalent: "")
        status.tag = 100
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        menu.addItem(makeItem("Bağlantı Ekranı…", #selector(showPairing), "k", tag: 0))
        let toggle = makeItem("Duraklat", #selector(toggleRunning), "e", tag: 101)
        menu.addItem(toggle)
        menu.addItem(.separator())

        let resolutionItem = NSMenuItem(title: "Ekran Çözünürlüğü", action: nil, keyEquivalent: "")
        let resolutionMenu = NSMenu()
        for (index, preset) in ResolutionPreset.allCases.enumerated() {
            let item = makeItem(
                "\(preset.title) — \(preset.detail)",
                #selector(setResolution(_:)),
                "",
                tag: 110 + index
            )
            resolutionMenu.addItem(item)
        }
        resolutionItem.submenu = resolutionMenu
        menu.addItem(resolutionItem)

        let fpsItem = NSMenuItem(title: "Kare Hızı", action: nil, keyEquivalent: "")
        let fpsMenu = NSMenu()
        fpsMenu.addItem(makeItem("60 fps", #selector(setFPS(_:)), "", tag: 120))
        fpsMenu.addItem(makeItem("30 fps", #selector(setFPS(_:)), "", tag: 121))
        fpsItem.submenu = fpsMenu
        menu.addItem(fpsItem)

        let bitrateItem = NSMenuItem(title: "Bit Hızı", action: nil, keyEquivalent: "")
        let bitrateMenu = NSMenu()
        let bitrates: [(Int, String)] = [
            (0, "Otomatik"),
            (8, "8 Mbps"),
            (12, "12 Mbps"),
            (20, "20 Mbps"),
            (30, "30 Mbps"),
            (40, "40 Mbps"),
        ]
        for (index, entry) in bitrates.enumerated() {
            bitrateMenu.addItem(makeItem(entry.1, #selector(setBitrate(_:)), "", tag: 130 + index))
        }
        bitrateItem.submenu = bitrateMenu
        menu.addItem(bitrateItem)
        menu.addItem(.separator())

        menu.addItem(makeItem("Dokunmatik fare", #selector(toggleInput), "", tag: 140))
        menu.addItem(makeItem("İmleci göster", #selector(toggleCursor), "", tag: 141))
        menu.addItem(.separator())

        menu.addItem(makeItem("Sunucuyu Yeniden Başlat", #selector(restartServer), "r", tag: 0))
        menu.addItem(makeItem("Eşleşme Kodunu Yenile", #selector(regenerateCode), "", tag: 0))
        menu.addItem(.separator())

        menu.addItem(makeItem("Ayarlar…", #selector(showSettings), ",", tag: 0))
        menu.addItem(makeItem("Hakkında", #selector(showAbout), "", tag: 0))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Çıkış", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func makeItem(_ title: String, _ action: Selector, _ key: String, tag: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.tag = tag
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        model.refresh()
        if let status = menu.item(withTag: 100) {
            status.title = "\(model.statusText) · \(model.resolutionText)"
        }
        if let toggle = menu.item(withTag: 101) {
            toggle.title = model.isRunning ? "Duraklat" : "Başlat"
        }

        let presets = ResolutionPreset.allCases
        for (index, preset) in presets.enumerated() {
            if let item = menu.item(withTag: 110 + index) {
                item.state = Preferences.shared.resolution == preset ? .on : .off
            }
        }
        menu.item(withTag: 120)?.state = Preferences.shared.fps == 60 ? .on : .off
        menu.item(withTag: 121)?.state = Preferences.shared.fps == 30 ? .on : .off

        let bitrates = [0, 8, 12, 20, 30, 40]
        for (index, value) in bitrates.enumerated() {
            menu.item(withTag: 130 + index)?.state = Preferences.shared.bitrateMbps == value ? .on : .off
        }
        menu.item(withTag: 140)?.state = Preferences.shared.inputEnabled ? .on : .off
        menu.item(withTag: 141)?.state = Preferences.shared.showCursor ? .on : .off
    }

    private func refreshStatusItem() {
        let connected = model.isConnected
        let symbol = connected ? "rectangle.on.rectangle.fill" : "rectangle.on.rectangle"
        statusItem?.button?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "Kodmoz Screen"
        )
        statusItem?.button?.image?.isTemplate = true
        statusItem?.button?.toolTip = "Kodmoz Screen — \(model.statusText)"
    }

    // MARK: - Eylemler

    @objc private func showPairing() {
        if pairingWindow == nil {
            let view = PairingView(model: model) { [weak self] in
                self?.showSettings()
            }
            let controller = NSHostingController(rootView: view)
            controller.sizingOptions = []
            let window = NSWindow(contentViewController: controller)
            window.title = "Kodmoz Screen"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 430, height: 420)
            window.setFrameAutosaveName("KodmozScreen.Pairing")
            let available = NSScreen.main?.visibleFrame.height ?? 900
            window.setContentSize(NSSize(width: 480, height: min(830, available - 70)))
            window.center()
            pairingWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        pairingWindow?.makeKeyAndOrderFront(nil)
        model.refresh()
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(model: model) { [weak self] in
                self?.settingsWindow?.close()
            }
            let controller = NSHostingController(rootView: view)
            controller.sizingOptions = []
            let window = NSWindow(contentViewController: controller)
            window.title = "Kodmoz Screen Ayarları"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 470, height: 660))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleRunning() {
        model.toggleRunning()
    }

    @objc private func setResolution(_ sender: NSMenuItem) {
        let presets = ResolutionPreset.allCases
        let index = sender.tag - 110
        guard presets.indices.contains(index) else { return }
        Preferences.shared.resolution = presets[index]
        if pipeline.isActive { pipeline.restart() } else { model.refresh() }
    }

    @objc private func setFPS(_ sender: NSMenuItem) {
        Preferences.shared.fps = sender.tag == 121 ? 30 : 60
        if pipeline.isActive { pipeline.restart() } else { model.refresh() }
    }

    @objc private func setBitrate(_ sender: NSMenuItem) {
        let values = [0, 8, 12, 20, 30, 40]
        let index = sender.tag - 130
        guard values.indices.contains(index) else { return }
        Preferences.shared.bitrateMbps = values[index]
        pipeline.updateBitrate()
        model.refresh()
    }

    @objc private func toggleInput() {
        Preferences.shared.inputEnabled.toggle()
        pipeline.injector.enabled = Preferences.shared.inputEnabled
        model.refresh()
    }

    @objc private func toggleCursor() {
        Preferences.shared.showCursor.toggle()
        if pipeline.isActive { pipeline.restart() } else { model.refresh() }
    }

    @objc private func restartServer() {
        model.restart()
    }

    @objc private func regenerateCode() {
        model.regenerateCode()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Kodmoz Screen"
        alert.informativeText = """
        Sürüm \(AppInfo.version) (\(AppInfo.build))

        Samsung tabletinizi WiFi veya USB üzerinden Mac'iniz için ikinci ekran olarak kullanın. Sanal ekran, donanım hızlandırmalı H.264 ve düşük gecikmeli TCP.

        MIT lisansı · github.com/hasanislamoglu5361/kodmoz-screen
        """
        alert.addButton(withTitle: "GitHub")
        alert.addButton(withTitle: "Tamam")
        if alert.runModal() == .alertFirstButtonReturn {
            model.openRepository()
        }
    }

    @objc private func screenParametersChanged() {
        displayChangeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.pipeline.handleScreenParametersChanged()
        }
        displayChangeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: item)
    }

    // MARK: - Ana menü (⌘Q, ⌘W, ⌘,)

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let about = NSMenuItem(title: "Kodmoz Screen Hakkında", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        appMenu.addItem(.separator())
        let settings = NSMenuItem(title: "Ayarlar…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Kodmoz Screen'i Gizle", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "Çıkış", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Pencere")
        windowMenu.addItem(NSMenuItem(title: "Küçült", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Kapat", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
    }
}
