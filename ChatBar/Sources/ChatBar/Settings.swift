import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    @Published var shortcut = Shortcut.load()
    @Published var recording = false
    @Published var error: String?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    var onShortcutChange: ((Shortcut) -> Bool)?
    var onRecordingChange: ((Bool) -> Void)?
    private var monitor: Any?

    func startRecording() {
        recording = true
        error = nil
        onRecordingChange?(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            if e.keyCode == 53 { self.stopRecording(); return nil } // Esc cancels
            guard let s = Shortcut(event: e) else {
                self.error = "Use at least one modifier: ⌘, ⌥ or ⌃"
                return nil
            }
            if self.onShortcutChange?(s) ?? false {
                self.shortcut = s
                s.save()
            } else {
                self.error = "\(s.display) is already used by another app"
            }
            self.stopRecording()
            return nil
        }
    }

    func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        onRecordingChange?(false)
    }

    func resetToDefault() {
        if onShortcutChange?(.default) ?? false {
            shortcut = .default
            shortcut.save()
            error = nil
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            self.error = "Launch at login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var chatgpt = ChatGPTControl.shared

    var body: some View {
        Form {
            Section("Hotkey") {
                LabeledContent("Open chat list") {
                    HStack {
                        Button(model.recording ? "Press shortcut…" : model.shortcut.display) {
                            model.recording ? model.stopRecording() : model.startRecording()
                        }
                        .frame(minWidth: 150)
                        Button("Reset (⌘Y)") { model.resetToDefault() }
                    }
                }
                Toggle("Launch ChatBar at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if let err = model.error {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
            }

            Section {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle().fill(Color(nsColor: chatgpt.status.color)).frame(width: 8, height: 8)
                        Text(chatgpt.status.label)
                    }
                }
                HStack {
                    Button(chatgpt.status == .notRunning ? "Launch ChatGPT with Port" : "Relaunch ChatGPT with Port") {
                        chatgpt.relaunchWithPort()
                    }
                    .disabled(chatgpt.busy || chatgpt.status == .withPort)
                    if chatgpt.busy { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Check Status") { chatgpt.refreshStatus() }
                }
            } header: {
                Text("ChatGPT")
            } footer: {
                Text("Regular ChatGPT chats open by ID only when ChatGPT runs with the debugging port "
                     + "(127.0.0.1:9333). Codex and Work threads open without it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize()
        .onAppear { chatgpt.refreshStatus() }
    }
}
