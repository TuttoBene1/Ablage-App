import AppKit
import ApplicationServices
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class QuickPasteModel: ObservableObject {
    @Published var query = "" {
        didSet { if oldValue != query { highlightedID = items.first?.id } }
    }
    @Published var highlightedID: UUID?
    @Published var canPaste = false
    @Published var scrollTick = 0
    @Published var focusTick = 0

    let store: ClipboardStore
    var onPick: ((ClipItem) -> Void)?
    private var lastKeyboardMove = Date.distantPast

    private static let digitKeys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                                    kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9].map(UInt16.init)

    init(store: ClipboardStore) {
        self.store = store
    }

    var items: [ClipItem] {
        store.items.filter { $0.pinned && $0.matches(query) } + store.items.filter { !$0.pinned && $0.matches(query) }
    }

    func reset() {
        query = ""
        highlightedID = items.first?.id
        focusTick += 1
    }

    func move(_ delta: Int) {
        let list = items
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == highlightedID } ?? (delta > 0 ? -1 : list.count)
        highlightedID = list[min(max(current + delta, 0), list.count - 1)].id
        lastKeyboardMove = Date()
        scrollTick += 1
    }

    func hover(_ id: UUID) {
        guard Date().timeIntervalSince(lastKeyboardMove) > 0.35 else { return }
        highlightedID = id
    }

    func pick(_ item: ClipItem) {
        onPick?(item)
    }

    func handleKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), let index = Self.digitKeys.firstIndex(of: event.keyCode) {
            let list = items
            if index < list.count { pick(list[index]) }
            return true
        }
        switch event.keyCode {
        case KeyCode.escape where !query.isEmpty: query = ""; return true
        case KeyCode.downArrow: move(1); return true
        case KeyCode.upArrow: move(-1); return true
        case KeyCode.return, KeyCode.enter:
            if let item = items.first(where: { $0.id == highlightedID }) ?? items.first { pick(item) }
            return true
        default: return false
        }
    }
}

@MainActor
final class QuickPasteController {
    static let size = CGSize(width: 340, height: 392)
    static let cornerRadius: CGFloat = 14

    let model: QuickPasteModel
    private let panel = FloatingPanel()
    private var outsideClickMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    init(store: ClipboardStore) {
        model = QuickPasteModel(store: store)
        let background = Chrome.background(radius: Self.cornerRadius)
        panel.contentView = background
        let host = FirstMouseHostingView(rootView: QuickPasteView(model: model, store: store))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        host.frame = background.bounds
        background.addSubview(host)

        panel.keyHandler = { [weak self] event in self?.model.handleKey(event) ?? false }
        panel.onCancel = { [weak self] in self?.close() }
        model.onPick = { [weak self] item in self?.paste(item) }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? close() : show()
    }

    func show() {
        AccessibilityAccess.requestOnce()
        model.canPaste = AccessibilityAccess.isTrusted
        model.reset()

        let anchor = CaretLocator.caretRect() ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
        let screen = NSScreen.screens.first { NSMouseInRect(CGPoint(x: anchor.midX, y: anchor.midY), $0.frame, false) }
            ?? NSScreen.containingMouse()
        panel.setFrame(Self.frame(near: anchor, size: Self.size, in: screen?.visibleFrame ?? .zero), display: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func close() {
        if let monitor = outsideClickMonitor { NSEvent.removeMonitor(monitor) }
        outsideClickMonitor = nil
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    static func frame(near anchor: CGRect, size: CGSize, in visible: CGRect) -> CGRect {
        let x = min(max(anchor.minX - 18, visible.minX + 8), visible.maxX - size.width - 8)
        var y = anchor.minY - 6 - size.height
        if y < visible.minY + 8 {
            y = min(anchor.maxY + 6, visible.maxY - size.height - 8)
        }
        return CGRect(x: round(x), y: round(y), width: size.width, height: size.height)
    }

    private func paste(_ item: ClipItem) {
        model.store.copyToPasteboard(item)
        close()
        guard AccessibilityAccess.isTrusted else {
            Toast.shared.show(symbol: "doc.on.clipboard", title: "Copied", subtitle: "Press ⌘V to paste", on: nil)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { KeyboardPaster.paste() }
    }
}

@MainActor
enum AccessibilityAccess {
    private static let askedKey = "didAskForAccessibility"

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestOnce() {
        guard !isTrusted, !UserDefaults.standard.bool(forKey: askedKey) else { return }
        UserDefaults.standard.set(true, forKey: askedKey)
        prompt()
    }

    static func openSettings() {
        prompt()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func prompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

@MainActor
enum CaretLocator {
    /// Text cursor (or small focused field) in Cocoa screen coordinates.
    static func caretRect() -> CGRect? {
        guard AXIsProcessTrusted(),
              let element = element(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute) else { return nil }
        guard let rect = caretBounds(of: element) ?? fieldFrame(of: element) else { return nil }
        return toCocoa(rect)
    }

    static func toCocoa(_ rect: CGRect, primaryHeight: CGFloat = NSScreen.screens.first?.frame.height ?? 0) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func caretBounds(of element: AXUIElement) -> CGRect? {
        guard let rangeValue = value(element, kAXSelectedTextRangeAttribute) else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range) else { return nil }
        let candidates = [range, CFRange(location: max(range.location - 1, 0), length: 1)]
        for candidate in candidates {
            var query = candidate
            guard let parameter = AXValueCreate(.cfRange, &query) else { continue }
            var result: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                             parameter, &result) == .success,
                  let result, CFGetTypeID(result) == AXValueGetTypeID() else { continue }
            var rect = CGRect.zero
            guard AXValueGetValue(result as! AXValue, .cgRect, &rect), rect.origin != .zero, rect.height > 0 else { continue }
            if candidate.location < range.location {
                rect.origin.x = rect.maxX
                rect.size.width = 0
            }
            return rect
        }
        return nil
    }

    private static func fieldFrame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = value(element, kAXPositionAttribute),
              let sizeValue = value(element, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &origin), AXValueGetValue(sizeValue, .cgSize, &size),
              size.height > 0, size.height <= 80 else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success,
              let result, CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success,
              let result, CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
        return (result as! AXValue)
    }
}

enum KeyboardPaster {
    static func paste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_ANSI_V)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown)
            event?.flags = .maskCommand
            event?.post(tap: .cgSessionEventTap)
        }
    }
}


struct QuickPasteView: View {
    @ObservedObject var model: QuickPasteModel
    @ObservedObject var store: ClipboardStore
    @FocusState private var searchFocused: Bool

    var body: some View {
        let items = model.items
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Paste from history", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($searchFocused)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)

            Divider().opacity(0.6)

            if items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: model.query.isEmpty ? "list.clipboard" : "magnifyingglass")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(model.query.isEmpty ? "Nothing copied yet" : "No results")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                QuickPasteRow(item: item, index: index, store: store,
                                              highlighted: model.highlightedID == item.id,
                                              onPick: { model.pick(item) },
                                              onHover: { model.hover(item.id) })
                                    .id(item.id)
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: model.scrollTick) {
                        guard let id = model.highlightedID else { return }
                        proxy.scrollTo(id)
                    }
                }
            }

            Divider().opacity(0.6)

            HStack(spacing: 14) {
                KeyHint(key: "↩", label: model.canPaste ? "Paste" : "Copy")
                KeyHint(key: "⌘1–9", label: "Pick")
                KeyHint(key: "esc", label: "Close")
                Spacer(minLength: 4)
                if !model.canPaste {
                    Button("Allow auto-paste") { AccessibilityAccess.openSettings() }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                        .help("Ablage needs Accessibility access to paste into other apps")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
        }
        .frame(width: QuickPasteController.size.width, height: QuickPasteController.size.height)
        .overlay(
            RoundedRectangle(cornerRadius: QuickPasteController.cornerRadius, style: .circular)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 0.5)
        )
        .onAppear { DispatchQueue.main.async { searchFocused = true } }
        .onChange(of: model.focusTick) { searchFocused = true }
    }
}

struct QuickPasteRow: View {
    let item: ClipItem
    let index: Int
    let store: ClipboardStore
    let highlighted: Bool
    let onPick: () -> Void
    let onHover: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ClipIcon(item: item, store: store, size: 24)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(item.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(highlighted ? 0.1 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onPick)
        .onHover { if $0 { onHover() } }
    }
}

struct KeyHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .frame(height: 16)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.08)))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }
}
