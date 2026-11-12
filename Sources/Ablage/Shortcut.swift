import AppKit
import Carbon.HIToolbox

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let screenshotDefault = Shortcut(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey))
    static let modifierMask = UInt32(cmdKey | shiftKey | optionKey | controlKey)

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Self.modifierMask
    }

    init(event: NSEvent) {
        self.init(keyCode: UInt32(event.keyCode), modifiers: Self.carbonModifiers(from: event.modifierFlags))
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    static func symbols(for modifiers: UInt32) -> String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text
    }

    var displayString: String { Self.symbols(for: modifiers) + KeyNames.name(for: keyCode) }
    var isFunctionKey: Bool { KeyNames.functionKeys[keyCode] != nil }
    var isUsableGlobally: Bool {
        if isFunctionKey { return true }
        return modifiers & UInt32(cmdKey | controlKey) != 0 && modifiers.nonzeroBitCount >= 2
    }

    var isUsedByMacOS: Bool {
        var ref: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&ref) == noErr,
              let list = ref?.takeRetainedValue() as? [[String: Any]] else { return false }
        return list.contains { item in
            guard (item[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true,
                  let code = (item[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint32Value,
                  let mods = (item[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value else { return false }
            return code == keyCode && (mods & Self.modifierMask) == modifiers
        }
    }
}

enum KeyNames {
    static let functionKeys: [UInt32: String] = {
        let codes = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                     kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        var names: [UInt32: String] = [:]
        for (index, code) in codes.enumerated() { names[UInt32(code)] = "F\(index + 1)" }
        return names
    }()

    private static let specialKeys: [UInt32: String] = [
        UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Delete): "⌫", UInt32(kVK_ForwardDelete): "⌦", UInt32(kVK_Escape): "⎋",
        UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→", UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓", UInt32(kVK_Home): "↖", UInt32(kVK_End): "↘",
        UInt32(kVK_PageUp): "⇞", UInt32(kVK_PageDown): "⇟",
    ]

    static func name(for keyCode: UInt32) -> String {
        if let name = functionKeys[keyCode] ?? specialKeys[keyCode] { return name }
        return character(for: keyCode)?.uppercased() ?? "#\(keyCode)"
    }

    private static func character(for keyCode: UInt32) -> String? {
        let sources = [TISCopyCurrentKeyboardLayoutInputSource(), TISCopyCurrentASCIICapableKeyboardLayoutInputSource()]
        for case let source? in sources {
            let input = source.takeRetainedValue()
            guard let raw = TISGetInputSourceProperty(input, kTISPropertyUnicodeKeyLayoutData) else { continue }
            let layoutData = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
            var deadKeys: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
                guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
                return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                      OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
            }
            if status == noErr, length > 0 {
                let text = String(utf16CodeUnits: chars, count: length).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
        }
        return nil
    }
}

enum ShortcutAction: String, CaseIterable, Identifiable {
    case screenshot, clipboard

    var id: String { rawValue }

    var hotKeyID: UInt32 { self == .screenshot ? 1 : 2 }

    init?(hotKeyID: UInt32) {
        guard let action = Self.allCases.first(where: { $0.hotKeyID == hotKeyID }) else { return nil }
        self = action
    }

    var title: String {
        switch self {
        case .screenshot: return "Take Screenshot"
        case .clipboard: return "Paste from History"
        }
    }

    var subtitle: String {
        switch self {
        case .screenshot: return "Starts the area selection in any app."
        case .clipboard: return "Opens your history at the text cursor."
        }
    }

    var defaultShortcut: Shortcut {
        switch self {
        case .screenshot: return .screenshotDefault
        case .clipboard: return .clipboardDefault
        }
    }

    var storageKey: String { "\(rawValue)Shortcut" }
}

extension Shortcut {
    static let clipboardDefault = Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | optionKey))
}

struct ShortcutMessage {
    let action: ShortcutAction
    let text: String
}

@MainActor
final class ShortcutSettings: ObservableObject {
    @Published private(set) var shortcuts: [ShortcutAction: Shortcut] = [:]
    @Published private(set) var recording: ShortcutAction?
    @Published private(set) var liveModifiers: UInt32 = 0
    @Published private(set) var message: ShortcutMessage?
    @Published private(set) var unavailable: Set<ShortcutAction> = []

    private let defaults: UserDefaults
    private let hotKeys: HotKeyCenter?
    private static let noneValue = "none"

    convenience init() {
        self.init(defaults: .standard, hotKeys: .shared)
    }

    init(defaults: UserDefaults, hotKeys: HotKeyCenter?) {
        self.defaults = defaults
        self.hotKeys = hotKeys
        for action in ShortcutAction.allCases {
            if defaults.string(forKey: action.storageKey) == Self.noneValue { continue }
            if let data = defaults.data(forKey: action.storageKey),
               let stored = try? JSONDecoder().decode(Shortcut.self, from: data) {
                shortcuts[action] = stored
            } else {
                shortcuts[action] = action.defaultShortcut
            }
        }
    }

    var screenshot: Shortcut? { shortcuts[.screenshot] }
    var isRecording: Bool { recording != nil }
    var hasChanges: Bool { ShortcutAction.allCases.contains { shortcuts[$0] != $0.defaultShortcut } }

    func shortcut(for action: ShortcutAction) -> Shortcut? { shortcuts[action] }

    func activate() {
        ShortcutAction.allCases.forEach(activate)
    }

    func startRecording(_ action: ShortcutAction) {
        if let current = recording, current != action { activate(current) }
        message = nil
        liveModifiers = 0
        recording = action
        hotKeys?.unregister(action)
    }

    func cancelRecording() {
        guard let action = recording else { return }
        recording = nil
        liveModifiers = 0
        activate(action)
    }

    func clear(_ action: ShortcutAction) {
        if recording == action { recording = nil }
        save(nil, for: action)
    }

    func resetToDefaults() {
        recording = nil
        message = nil
        for action in ShortcutAction.allCases { save(action.defaultShortcut, for: action) }
    }

    func handle(_ event: NSEvent) -> Bool {
        guard let action = recording else { return false }
        if event.type == .flagsChanged {
            liveModifiers = Shortcut.carbonModifiers(from: event.modifierFlags)
            return true
        }
        guard event.type == .keyDown else { return false }
        let shortcut = Shortcut(event: event)
        switch (shortcut.keyCode, shortcut.modifiers) {
        case (UInt32(kVK_Escape), 0):
            cancelRecording()
        case (UInt32(kVK_Delete), 0), (UInt32(kVK_ForwardDelete), 0):
            clear(action)
        default:
            if shortcut.isUsableGlobally {
                apply(shortcut, for: action)
            } else {
                message = ShortcutMessage(action: action, text: "Use two modifier keys including ⌘ or ⌃ (like ⇧⌘2) – or a function key such as F13.")
            }
        }
        return true
    }

    private func apply(_ shortcut: Shortcut, for action: ShortcutAction) {
        recording = nil
        liveModifiers = 0
        if let other = ShortcutAction.allCases.first(where: { $0 != action && shortcuts[$0] == shortcut }) {
            message = ShortcutMessage(action: action, text: "\(shortcut.displayString) is already used for “\(other.title)”.")
            activate(action)
            return
        }
        if shortcut.isUsedByMacOS {
            message = ShortcutMessage(action: action, text: "\(shortcut.displayString) is used by macOS. Turn it off in System Settings › Keyboard › Keyboard Shortcuts first.")
            activate(action)
            return
        }
        save(shortcut, for: action)
    }

    private func save(_ shortcut: Shortcut?, for action: ShortcutAction) {
        shortcuts[action] = shortcut
        if let shortcut, let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: action.storageKey)
        } else {
            defaults.set(Self.noneValue, forKey: action.storageKey)
        }
        if message?.action == action { message = nil }
        activate(action)
    }

    private func activate(_ action: ShortcutAction) {
        guard let hotKeys else { return }
        let status = hotKeys.register(shortcuts[action], for: action)
        if status == noErr {
            unavailable.remove(action)
        } else {
            unavailable.insert(action)
            NSLog("Ablage: could not register %@ (%d)", shortcuts[action]?.displayString ?? "", status)
        }
    }
}
