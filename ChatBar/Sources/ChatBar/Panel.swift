import AppKit
import SwiftUI

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Spotlight-style panel: does not activate the app and hides when it loses focus.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let panel: KeyPanel
    private let store: ChatStore
    private let state = PanelState()
    private var keyMonitor: Any?

    init(store: ChatStore) {
        self.store = store
        panel = KeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 440),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        let view = PanelView(store: store, state: state) { [weak self] item in self?.open(item) }
        panel.contentView = NSHostingView(rootView: view)
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        state.query = ""
        state.selection = 0
        store.refresh()
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: f.midX - 340, y: f.minY + f.height * 0.62 - 220))
        }
        panel.makeKeyAndOrderFront(nil)
        state.focusNonce += 1
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private var results: [ChatItem] { PanelView.filter(store.items, state.query) }

    private func open(_ item: ChatItem) {
        hide()
        Opener.open(item)
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.panel.isKeyWindow else { return e }
            let count = self.results.count
            switch Int(e.keyCode) {
            case 125: // ↓
                if count > 0 { self.state.selection = min(self.state.selection + 1, count - 1) }
                return nil
            case 126: // ↑
                self.state.selection = max(self.state.selection - 1, 0)
                return nil
            case 36, 76: // Return, Enter
                if self.results.indices.contains(self.state.selection) { self.open(self.results[self.state.selection]) }
                return nil
            case 53: // Esc
                self.hide()
                return nil
            default:
                return e
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
