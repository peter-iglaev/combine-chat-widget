import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ChatStore()
    private var panel: PanelController!
    private var hotKey: HotKeyManager!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private let settings = SettingsModel()
    private var openItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = PanelController(store: store)
        hotKey = HotKeyManager { [weak self] in self?.panel.toggle() }
        hotKey.register(settings.shortcut)

        settings.onShortcutChange = { [weak self] s in
            guard let self else { return false }
            let ok = self.hotKey.register(s)
            if !ok { self.hotKey.register(self.settings.shortcut) }
            self.updateMenuTitle(ok ? s : self.settings.shortcut)
            return ok
        }
        // While recording a new shortcut, the old one must not open the panel.
        settings.onRecordingChange = { [weak self] recording in
            guard let self else { return }
            if recording { self.hotKey.unregister() } else { self.hotKey.register(self.settings.shortcut) }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "bubble.left.and.bubble.right", accessibilityDescription: "ChatBar")
        let menu = NSMenu()
        openItem = NSMenuItem(title: "", action: #selector(showPanel), keyEquivalent: "")
        menu.addItem(openItem)
        menu.addItem(NSMenuItem(title: "Обновить список", action: #selector(refresh), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Перезапустить ChatGPT с портом", action: #selector(relaunchChatGPT), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Настройки…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Выйти из ChatBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items { item.target = item.action == #selector(NSApplication.terminate(_:)) ? NSApp : self }
        statusItem.menu = menu
        updateMenuTitle(settings.shortcut)

        store.refresh()
    }

    private func updateMenuTitle(_ s: Shortcut) {
        openItem.title = "Открыть список чатов (\(s.display))"
    }

    @objc private func showPanel() { panel.show() }

    @objc private func refresh() { store.refresh() }

    @objc private func relaunchChatGPT() { ChatGPTControl.shared.relaunchWithPort() }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: settings)))
            w.title = "ChatBar — настройки"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            settingsWindow = w
        }
        settingsWindow?.center()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
