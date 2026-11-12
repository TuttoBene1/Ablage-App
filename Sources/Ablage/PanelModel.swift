import AppKit
import Combine
import ServiceManagement

@MainActor
final class PanelModel: ObservableObject {
    enum Route { case home, clipboard, shortcut }

    @Published var route: Route = .home
    @Published var query = "" {
        didSet { if oldValue != query { highlightedID = visibleItems.first?.id } }
    }
    @Published var highlightedID: UUID?
    @Published var copiedID: UUID?
    @Published var keyboardScrollTick = 0
    @Published var focusSearchTick = 0

    let store: ClipboardStore
    let shortcuts: ShortcutSettings

    var onScreenshot: (() -> Void)?
    var onClose: (() -> Void)?
    var onQuit: (() -> Void)?

    init(store: ClipboardStore, shortcuts: ShortcutSettings) {
        self.store = store
        self.shortcuts = shortcuts
    }

    var pinnedItems: [ClipItem] { store.items.filter { $0.pinned && $0.matches(query) } }
    var recentItems: [ClipItem] { store.items.filter { !$0.pinned && $0.matches(query) } }
    var visibleItems: [ClipItem] { pinnedItems + recentItems }

    func showClipboard() {
        query = ""
        highlightedID = visibleItems.first?.id
        route = .clipboard
        focusSearchTick += 1
    }

    func showHome() {
        shortcuts.cancelRecording()
        route = .home
    }

    func showShortcut() {
        route = .shortcut
    }

    func reset() {
        shortcuts.cancelRecording()
        route = .home
        query = ""
        copiedID = nil
        highlightedID = nil
    }

    private var lastKeyboardMove = Date.distantPast

    func moveHighlight(_ delta: Int) {
        let items = visibleItems
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == highlightedID } ?? (delta > 0 ? -1 : items.count)
        let next = min(max(current + delta, 0), items.count - 1)
        highlightedID = items[next].id
        lastKeyboardMove = Date()
        keyboardScrollTick += 1
    }

    func hover(_ id: UUID) {
        guard Date().timeIntervalSince(lastKeyboardMove) > 0.35 else { return }
        highlightedID = id
    }

    func copyHighlighted() {
        guard let item = visibleItems.first(where: { $0.id == highlightedID }) ?? visibleItems.first else { return }
        copy(item)
    }

    func copy(_ item: ClipItem) {
        guard copiedID == nil else { return }
        store.copyToPasteboard(item)
        copiedID = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { [weak self] in
            self?.onClose?()
        }
    }

    func handleKey(_ event: NSEvent) -> Bool {
        if route == .shortcut { return shortcuts.handle(event) }
        guard route == .clipboard, event.type == .keyDown else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case KeyCode.escape where !query.isEmpty: query = ""; return true
        case KeyCode.downArrow: moveHighlight(1); return true
        case KeyCode.upArrow: moveHighlight(-1); return true
        case KeyCode.return, KeyCode.enter: copyHighlighted(); return true
        case KeyCode.delete where flags.contains(.command):
            if let id = highlightedID { delete(id) }
            return true
        case KeyCode.p where flags.contains(.command):
            if let id = highlightedID { store.togglePin(id) }
            return true
        default: return false
        }
    }

    func delete(_ id: UUID) {
        let items = visibleItems
        let index = items.firstIndex { $0.id == id }
        store.delete(id)
        let remaining = visibleItems
        if let index, !remaining.isEmpty {
            highlightedID = remaining[min(index, remaining.count - 1)].id
        }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Ablage: login item change failed: \(error.localizedDescription)")
            }
            objectWillChange.send()
        }
    }
}
