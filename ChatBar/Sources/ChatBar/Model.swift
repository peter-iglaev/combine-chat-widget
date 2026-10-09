import AppKit
import Foundation

enum ChatSource: String, Codable, CaseIterable {
    case claudeChat = "claude_chat"
    case claudeCode = "claude_code"
    case cowork
    case chatgpt
    case work
    case codex

    var label: String {
        switch self {
        case .claudeChat: return "Claude"
        case .claudeCode: return "Code"
        case .cowork: return "Cowork"
        case .chatgpt: return "ChatGPT"
        case .work: return "Work"
        case .codex: return "Codex"
        }
    }

    var appPath: String {
        switch self {
        case .claudeChat, .claudeCode, .cowork: return "/Applications/Claude.app"
        case .chatgpt, .work, .codex: return "/Applications/ChatGPT.app"
        }
    }
}

struct ChatItem: Codable, Identifiable, Hashable {
    let id: String
    let source: ChatSource
    let title: String
    let updated: Int64
    let url: String?
    let gptId: String?

    var updatedDate: Date { Date(timeIntervalSince1970: TimeInterval(updated) / 1000) }
}

/// The collector and its Python interpreter are embedded in the app bundle by scripts/build.sh.
enum Paths {
    static var python: String {
        Bundle.main.resourceURL!.appendingPathComponent("python/bin/python3").path
    }

    static var collector: String {
        Bundle.main.resourceURL!.appendingPathComponent("collector/chatbar.py").path
    }

    static var cacheFile: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChatBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return dir.appendingPathComponent("items.json")
    }
}

struct ProcessResult {
    let status: Int32
    let stdout: Data
    let stderr: String
}

func runCollector(_ args: [String]) async -> ProcessResult {
    await withCheckedContinuation { cont in
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Paths.python)
        p.arguments = ["-I", "-B", Paths.collector] + args  // -B: never write .pyc into the signed bundle
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do {
            try p.run()
        } catch {
            cont.resume(returning: ProcessResult(status: -1, stdout: Data(), stderr: "\(error)"))
            return
        }
        // Drain the pipes while the process runs: output over 64 KB would otherwise block the collector.
        DispatchQueue.global(qos: .userInitiated).async {
            var e = Data()
            let errReader = DispatchQueue(label: "chatbar.stderr")
            errReader.async { e = err.fileHandleForReading.readDataToEndOfFile() }
            let o = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            errReader.sync {}
            let es = String(data: e, encoding: .utf8) ?? ""
            cont.resume(returning: ProcessResult(status: p.terminationStatus, stdout: o, stderr: es))
        }
    }
}

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var items: [ChatItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    init() {
        if let data = try? Data(contentsOf: Paths.cacheFile),
           let cached = try? JSONDecoder().decode([ChatItem].self, from: data) {
            items = cached
        }
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            let r = await runCollector(["list"])
            isLoading = false
            guard r.status == 0, let list = try? JSONDecoder().decode([ChatItem].self, from: r.stdout) else {
                lastError = r.stderr.isEmpty ? "Сборщик завершился с кодом \(r.status)" : r.stderr
                return
            }
            lastError = nil
            items = list
            // The cache contains chat titles: owner-only access.
            try? r.stdout.write(to: Paths.cacheFile)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Paths.cacheFile.path)
        }
    }
}
