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

@MainActor
final class ShortcutSettings: ObservableObject {
    @Published private(set) var screenshot: Shortcut?
    @Published private(set) var isRecording = false
    @Published private(set) var liveModifiers: UInt32 = 0
    @Published private(set) var message: String?
    @Published private(set) var isAvailable = true

    private let defaults: UserDefaults
    private let hotKeys: HotKeyCenter?
    private static let storageKey = "screenshotShortcut"
    private static let noneValue = "none"

    convenience init() {
        self.init(defaults: .standard, hotKeys: .shared)
    }

    init(defaults: UserDefaults, hotKeys: HotKeyCenter?) {
        self.defaults = defaults
        self.hotKeys = hotKeys
        if defaults.string(forKey: Self.storageKey) == Self.noneValue {
            screenshot = nil
        } else if let data = defaults.data(forKey: Self.storageKey),
                  let stored = try? JSONDecoder().decode(Shortcut.self, from: data) {
            screenshot = stored
        } else {
            screenshot = .screenshotDefault
        }
    }

    var isDefault: Bool { screenshot == .screenshotDefault }

    func activate() {
        isAvailable = register(screenshot)
    }

    func startRecording() {
        message = nil
        liveModifiers = 0
        isRecording = true
        hotKeys?.unregister()
    }

    func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        liveModifiers = 0
        activate()
    }

    func clear() {
        isRecording = false
        save(nil)
    }

    func resetToDefault() {
        isRecording = false
        apply(.screenshotDefault)
    }

    func handle(_ event: NSEvent) -> Bool {
        guard isRecording else { return false }
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
            clear()
        default:
            if shortcut.isUsableGlobally {
                apply(shortcut)
            } else {
                message = "Use two modifier keys including ⌘ or ⌃ (like ⇧⌘2) – or a function key such as F13."
            }
        }
        return true
    }

    private func apply(_ shortcut: Shortcut) {
        isRecording = false
        liveModifiers = 0
        if shortcut.isUsedByMacOS {
            message = "\(shortcut.displayString) is used by macOS. Turn it off in System Settings › Keyboard › Keyboard Shortcuts first."
            activate()
            return
        }
        guard register(shortcut) else {
            message = "\(shortcut.displayString) is already used by another app."
            activate()
            return
        }
        save(shortcut)
    }

    private func save(_ shortcut: Shortcut?) {
        screenshot = shortcut
        if let shortcut, let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: Self.storageKey)
        } else {
            defaults.set(Self.noneValue, forKey: Self.storageKey)
        }
        message = nil
        activate()
    }

    private func register(_ shortcut: Shortcut?) -> Bool {
        guard let hotKeys else { return true }
        let status = hotKeys.register(shortcut)
        if status != noErr { NSLog("Ablage: could not register %@ (%d)", shortcut?.displayString ?? "", status) }
        return status == noErr
    }
}
