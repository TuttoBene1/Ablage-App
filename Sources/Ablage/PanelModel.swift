import AppKit
import Combine
import ServiceManagement

@MainActor
final class PanelModel: ObservableObject {
    enum Route { case home, clipboard }

    @Published var route: Route = .home
    @Published var query = "" {
        didSet { if oldValue != query { highlightedID = visibleItems.first?.id } }
    }
    @Published var highlightedID: UUID?
    @Published var copiedID: UUID?
    /// Bumped when the keyboard moves the selection, so the list scrolls along.
    @Published var keyboardScrollTick = 0
    @Published var focusSearchTick = 0

    let store: ClipboardStore

    var onScreenshot: (() -> Void)?
    var onClose: (() -> Void)?
    var onQuit: (() -> Void)?

    init(store: ClipboardStore) {
        self.store = store
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
        route = .home
    }

    func reset() {
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

    /// Mouse hover selects a row, unless the keyboard just moved the selection
    /// (rows scrolling under a resting pointer would otherwise steal it).
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

    /// Keyboard handling for the panel. Returns true when the event was consumed.
    func handleKey(_ event: NSEvent) -> Bool {
        guard route == .clipboard else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 53 where !query.isEmpty: query = ""; return true // esc clears the search first
        case 125: moveHighlight(1); return true            // ↓
        case 126: moveHighlight(-1); return true           // ↑
        case 36, 76: copyHighlighted(); return true        // ↩ / enter
        case 51 where flags.contains(.command):              // ⌘⌫ delete entry
            if let id = highlightedID { delete(id) }
            return true
        case 35 where flags.contains(.command):              // ⌘P pin
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

    // MARK: Login item

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
