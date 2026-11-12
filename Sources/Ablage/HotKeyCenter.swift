import AppKit
import Carbon.HIToolbox

@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var onPress: ((ShortcutAction) -> Void)?
    private var hotKeys: [ShortcutAction: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let action = status == noErr ? ShortcutAction(hotKeyID: hotKeyID.id) ?? .screenshot : .screenshot
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HotKeyCenter.shared.onPress?(action) }
            }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    func register(_ shortcut: Shortcut?, for action: ShortcutAction) -> OSStatus {
        unregister(action)
        guard let shortcut else { return noErr }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: 0x41424C47, id: action.hotKeyID) // 'ABLG'
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id,
                                         GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref)
        if status == noErr, let ref { hotKeys[action] = ref }
        return status
    }

    func unregister(_ action: ShortcutAction) {
        if let ref = hotKeys.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
    }

    func unregisterAll() {
        ShortcutAction.allCases.forEach(unregister)
    }
}
