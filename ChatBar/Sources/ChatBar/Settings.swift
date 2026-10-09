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
            if e.keyCode == 53 { self.stopRecording(); return nil } // Esc отменяет
            guard let s = Shortcut(event: e) else {
                self.error = "Нужен хотя бы один модификатор: ⌘, ⌥ или ⌃"
                return nil
            }
            if self.onShortcutChange?(s) ?? false {
                self.shortcut = s
                s.save()
            } else {
                self.error = "Сочетание \(s.display) занято другим приложением"
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
            self.error = "Автозапуск: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            LabeledContent("Хоткей") {
                HStack {
                    Button(model.recording ? "Нажмите сочетание…" : model.shortcut.display) {
                        model.recording ? model.stopRecording() : model.startRecording()
                    }
                    .frame(minWidth: 160)
                    Button("По умолчанию (⌘Y)") { model.resetToDefault() }
                }
            }
            Toggle("Запускать при входе в систему", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            if let err = model.error {
                Text(err).foregroundStyle(.red).font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }
}
