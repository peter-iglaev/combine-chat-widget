import AppKit

/// State of ChatGPT.app with respect to the local debugging port used to open chats by id.
enum ChatGPTStatus: Equatable {
    case checking
    case withPort
    case withoutPort
    case notRunning

    var label: String {
        switch self {
        case .checking: return "Checking…"
        case .withPort: return "Running with port: chats open by ID"
        case .withoutPort: return "Running without port: regular ChatGPT chats won't open"
        case .notRunning: return "Not running"
        }
    }

    var color: NSColor {
        switch self {
        case .withPort: return .systemGreen
        case .withoutPort: return .systemOrange
        case .checking, .notRunning: return .secondaryLabelColor
        }
    }
}

@MainActor
final class ChatGPTControl: ObservableObject {
    static let shared = ChatGPTControl()

    @Published private(set) var status: ChatGPTStatus = .checking
    @Published private(set) var busy = false

    private static let appPath = "/Applications/ChatGPT.app"

    private var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.path == Self.appPath }
    }

    func refreshStatus() {
        Task { status = await currentStatus() }
    }

    private func currentStatus() async -> ChatGPTStatus {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:9333/json/version")!)
        req.timeoutInterval = 1
        if let (_, resp) = try? await URLSession.shared.data(for: req),
           (resp as? HTTPURLResponse)?.statusCode == 200 {
            return .withPort
        }
        return isRunning ? .withoutPort : .notRunning
    }

    /// Asks before quitting a running ChatGPT, then (re)launches it with the debugging port.
    func relaunchWithPort(confirm: Bool = true) {
        guard !busy else { return }
        if confirm && isRunning && !Self.confirmRelaunch() { return }
        busy = true
        status = .checking
        Task {
            let r = await runCollector(["launch-gpt"])
            busy = false
            status = await currentStatus()
            if r.status != 0 { Self.showError("Couldn't launch ChatGPT with the debugging port", r.stderr) }
        }
    }

    static func confirmRelaunch() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Relaunch ChatGPT?"
        alert.informativeText = "ChatGPT will quit and reopen with the debugging port "
            + "so ChatBar can open chats by ID. Codex tasks that are currently running will be interrupted."
        alert.addButton(withTitle: "Relaunch")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func showError(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text.isEmpty ? "Unknown error" : text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
