import AppKit
import Carbon.HIToolbox

/// Сочетание клавиш в формате Carbon: keyCode + модификаторы.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var keyLabel: String

    static let `default` = Shortcut(keyCode: UInt32(kVK_ANSI_Y), modifiers: UInt32(cmdKey), keyLabel: "Y")

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + keyLabel
    }

    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    /// nil, если в событии нет ни ⌘, ни ⌥, ни ⌃: одиночные клавиши как глобальный хоткей не берём.
    init?(event: NSEvent) {
        let f = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var m: UInt32 = 0
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        guard m & UInt32(cmdKey | optionKey | controlKey) != 0 else { return nil }
        let label: String
        switch Int(event.keyCode) {
        case kVK_Space: label = "Space"
        case kVK_Return: label = "↩"
        case kVK_Tab: label = "⇥"
        default: label = (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
        self.init(keyCode: UInt32(event.keyCode), modifiers: m, keyLabel: label)
    }

    private static let defaultsKey = "hotkey"

    static func load() -> Shortcut {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let s = try? JSONDecoder().decode(Shortcut.self, from: data) else { return .default }
        return s
    }

    func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: Shortcut.defaultsKey)
    }
}

/// Глобальный хоткей через Carbon RegisterEventHotKey: не требует права Accessibility.
final class HotKeyManager {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let me = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.action() }
            return noErr
        }, 1, &spec, selfPtr, &handler)
    }

    @discardableResult
    func register(_ s: Shortcut) -> Bool {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        let id = EventHotKeyID(signature: OSType(0x4348_4252), id: 1) // 'CHBR'
        let status = RegisterEventHotKey(s.keyCode, s.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}
