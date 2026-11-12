import AppKit
import SwiftUI

final class SelectionWindow: NSPanel {
    let targetScreen: NSScreen
    private let selectionView: SelectionView

    @MainActor
    init(screen: NSScreen, controller: CaptureController, showsToolbar: Bool, frozenImage: CGImage? = nil) {
        targetScreen = screen
        selectionView = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        selectionView.controller = controller
        selectionView.targetScreen = screen
        contentView = selectionView
        if let frozenImage { selectionView.showFrozen(frozenImage) }
        if showsToolbar { selectionView.installToolbar(controller: controller) }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func present() {
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            animator().alphaValue = 1
        }
    }

    func activate() {
        makeKeyAndOrderFront(nil)
        makeFirstResponder(selectionView)
    }
}

final class SelectionView: NSView {
    weak var controller: CaptureController?
    var targetScreen: NSScreen?

    private let shapes = SelectionShapeView()
    private let badge = SizeBadge()
    private var toolbar: NSView?
    private var startPoint: CGPoint?
    private var selection: CGRect?

    override init(frame: NSRect) {
        super.init(frame: frame)
        shapes.frame = bounds
        shapes.autoresizingMask = [.width, .height]
        addSubview(shapes)
        badge.isHidden = true
        addSubview(badge)
        updateLayers()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func showFrozen(_ image: CGImage) {
        let frozen = FrozenScreenView(frame: bounds, image: image)
        frozen.autoresizingMask = [.width, .height]
        addSubview(frozen, positioned: .below, relativeTo: shapes)
    }

    override func layout() {
        super.layout()
        updateLayers()
    }

    func installToolbar(controller: CaptureController) {
        let host = FirstMouseHostingView(rootView: CaptureToolbar(controller: controller))
        let size = host.fittingSize
        let dockInset = targetScreen.map { $0.visibleFrame.minY - $0.frame.minY } ?? 0
        host.frame = NSRect(x: ((bounds.width - size.width) / 2).rounded(),
                            y: (dockInset + 24).rounded(),
                            width: size.width, height: size.height)
        addSubview(host)
        toolbar = host
    }

    private func updateLayers() {
        shapes.update(selection: selection)
    }

    private func updateBadge(cursor: CGPoint) {
        guard let selection else { badge.isHidden = true; return }
        badge.text = "\(Int(selection.width)) × \(Int(selection.height))"
        let size = badge.preferredSize
        var origin = CGPoint(x: cursor.x + 14, y: cursor.y - size.height - 12)
        if origin.x + size.width > bounds.maxX - 6 { origin.x = cursor.x - size.width - 14 }
        if origin.y < bounds.minY + 6 { origin.y = cursor.y + 14 }
        badge.frame = NSRect(origin: origin, size: size).integral
        badge.isHidden = false
    }

    private var toolbarHitRect: NSRect? {
        guard let toolbar, toolbar.alphaValue > 0.5 else { return nil }
        return toolbar.frame.insetBy(dx: CaptureToolbar.margin, dy: CaptureToolbar.margin)
    }

    private func setToolbarHidden(_ hidden: Bool) {
        guard let toolbar else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            toolbar.animator().alphaValue = hidden ? 0 : 1
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .cursorUpdate, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor(event) }
    override func mouseMoved(with event: NSEvent) { updateCursor(event) }
    override func mouseEntered(with event: NSEvent) { updateCursor(event) }

    private func updateCursor(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if startPoint == nil, let rect = toolbarHitRect, rect.contains(point) {
            NSCursor.arrow.set()
        } else {
            NSCursor.crosshair.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        let point = clamped(convert(event.locationInWindow, from: nil))
        startPoint = point
        selection = CGRect(origin: point, size: .zero)
        NSCursor.crosshair.set()
        setToolbarHidden(true)
        updateLayers()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let point = clamped(convert(event.locationInWindow, from: nil))
        let minX = floor(min(start.x, point.x))
        let minY = floor(min(start.y, point.y))
        let maxX = ceil(max(start.x, point.x))
        let maxY = ceil(max(start.y, point.y))
        selection = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        updateLayers()
        updateBadge(cursor: point)
    }

    override func mouseUp(with event: NSEvent) {
        guard startPoint != nil, let rect = selection else { return }
        startPoint = nil
        guard rect.width >= 4, rect.height >= 4, let screen = targetScreen else {
            selection = nil
            badge.isHidden = true
            setToolbarHidden(false)
            updateLayers()
            return
        }
        let topLeft = CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
        controller?.complete(rect: topLeft, on: screen)
    }

    override func rightMouseDown(with event: NSEvent) {
        if startPoint == nil { controller?.cancel() }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case KeyCode.escape: controller?.cancel()
        case KeyCode.v where startPoint == nil: controller?.mode = .video
        case KeyCode.p where startPoint == nil, KeyCode.f where startPoint == nil:
            controller?.mode = .photo
        default: break
        }
    }

    override func cancelOperation(_ sender: Any?) {
        controller?.cancel()
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), bounds.width), y: min(max(point.y, 0), bounds.height))
    }
}

final class SelectionShapeView: NSView {
    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let root = CALayer()
        layer = root

        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.32).cgColor
        root.addSublayer(dimLayer)

        borderLayer.fillColor = nil
        borderLayer.strokeColor = NSColor.white.withAlphaComponent(0.95).cgColor
        borderLayer.lineWidth = 1
        borderLayer.shadowColor = NSColor.black.cgColor
        borderLayer.shadowOpacity = 0.4
        borderLayer.shadowRadius = 1.5
        borderLayer.shadowOffset = .zero
        root.addSublayer(borderLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let scale = window?.backingScaleFactor ?? 2
        dimLayer.contentsScale = scale
        borderLayer.contentsScale = scale
    }

    func update(selection: CGRect?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dimLayer.frame = bounds
        borderLayer.frame = bounds
        let path = CGMutablePath()
        path.addRect(bounds)
        if let selection, selection.width >= 1, selection.height >= 1 {
            path.addRect(selection)
            borderLayer.path = CGPath(rect: selection.insetBy(dx: -0.5, dy: -0.5), transform: nil)
            borderLayer.isHidden = false
        } else {
            borderLayer.isHidden = true
        }
        dimLayer.path = path
        CATransaction.commit()
    }
}

final class FrozenScreenView: NSView {
    init(frame: NSRect, image: CGImage) {
        super.init(frame: frame)
        wantsLayer = true
        let layer = CALayer()
        layer.contents = image
        layer.contentsGravity = .resize
        self.layer = layer
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class SizeBadge: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    var text = "" { didSet { if text != oldValue { needsDisplay = true } } }

    private var attributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
         .foregroundColor: NSColor.white]
    }

    var preferredSize: NSSize {
        let size = (text as NSString).size(withAttributes: attributes)
        return NSSize(width: ceil(size.width) + 16, height: 20)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                            y: (bounds.height - size.height) / 2),
                                withAttributes: attributes)
    }
}

struct CaptureToolbar: View {
    static let margin: CGFloat = 24
    @ObservedObject var controller: CaptureController

    var body: some View {
        HStack(spacing: 2) {
            ModeButton(title: "Photo", symbol: "camera", selectedSymbol: "camera.fill",
                       tint: .white, selected: controller.mode == .photo) {
                controller.mode = .photo
            }
            .help("Photo (P)")
            ModeButton(title: "Video", symbol: "record.circle", selectedSymbol: "record.circle.fill",
                       tint: Color(red: 1, green: 0.27, blue: 0.23), selected: controller.mode == .video) {
                controller.mode = .video
            }
            .help("Video (V)")

            Rectangle()
                .fill(Color.white.opacity(0.16))
                .frame(width: 1, height: 18)
                .padding(.horizontal, 6)

            CloseButton { controller.cancel() }
                .help("Cancel (esc)")
        }
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color(white: 0.1).opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.white.opacity(0.13), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 14, y: 5)
        .padding(Self.margin)
        .environment(\.colorScheme, .dark)
    }
}

private struct ModeButton: View {
    let title: String
    let symbol: String
    let selectedSymbol: String
    let tint: Color
    let selected: Bool
    let action: () -> Void
    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: selected ? selectedSymbol : symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? tint : Color.white.opacity(0.62))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.62))
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.17 : (hover.on ? 0.07 : 0)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
        .animation(.easeOut(duration: 0.12), value: selected)
    }
}

private struct CloseButton: View {
    let action: () -> Void
    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.75))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(hover.on ? 0.16 : 0.09)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
        .padding(.trailing, 2)
    }
}
