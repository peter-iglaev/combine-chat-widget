import AppKit

@MainActor
enum Opener {
    static func open(_ item: ChatItem) {
        if let gptId = item.gptId {
            openChatGPT(gptId, relaunch: false)
            return
        }
        guard let s = item.url, let url = URL(string: s) else { return }
        // У старого Codex.app та же схема codex://, поэтому приложение указываем явно.
        let app = URL(fileURLWithPath: item.source.appPath)
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func openChatGPT(_ id: String, relaunch: Bool) {
        Task {
            let r = await runCollector(["open-gpt", id] + (relaunch ? ["--relaunch"] : []))
            switch r.status {
            case 0:
                return
            case 3:
                if confirmRelaunch() { openChatGPT(id, relaunch: true) }
            default:
                showError(r.stderr)
            }
        }
    }

    private static func confirmRelaunch() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Перезапустить ChatGPT?"
        alert.informativeText = "ChatGPT запущен без отладочного порта, поэтому открыть чат по ID нельзя. "
            + "ChatBar перезапустит его с портом. Задачи Codex, которые сейчас выполняются, прервутся."
        alert.addButton(withTitle: "Перезапустить")
        alert.addButton(withTitle: "Отмена")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func showError(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "Не удалось открыть чат ChatGPT"
        alert.informativeText = text.isEmpty ? "Неизвестная ошибка" : text
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
