import AppKit

@MainActor
enum Opener {
    static func open(_ item: ChatItem) {
        if let gptId = item.gptId {
            openChatGPT(gptId, relaunch: false)
            return
        }
        guard let s = item.url, let url = URL(string: s) else { return }
        // The legacy Codex.app registers the same codex:// scheme, so target the app explicitly.
        let app = URL(fileURLWithPath: item.source.appPath)
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func openChatGPT(_ id: String, relaunch: Bool) {
        Task {
            let r = await runCollector(["open-gpt", id] + (relaunch ? ["--relaunch"] : []))
            switch r.status {
            case 0:
                ChatGPTControl.shared.refreshStatus()
            case 3:
                if ChatGPTControl.confirmRelaunch() { openChatGPT(id, relaunch: true) }
            default:
                ChatGPTControl.showError("Не удалось открыть чат ChatGPT", r.stderr)
            }
        }
    }
}
