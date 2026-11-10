import AppKit
import SwiftUI

@MainActor
final class EditorController {
    private static var openEditors: [EditorController] = []
    static let cornerRadius: CGFloat = 16
    static let toolbarHeight: CGFloat = 52

    let doc: EditorDocument
    private let panel = FloatingPanel()

    static func open(image: CGImage, pointSize: CGSize, screen: NSScreen?) {
        let editor = EditorController(image: image, pointSize: pointSize)
        openEditors.append(editor)
        editor.show(on: screen)
    }

    private init(image: CGImage, pointSize: CGSize) {
        doc = EditorDocument(image: image, pointSize: pointSize)
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.hidesOnDeactivate = false

        let background = Chrome.background(radius: Self.cornerRadius, material: .windowBackground)
        panel.contentView = background
        let view = EditorView(doc: doc,
                              onCancel: { [weak self] in self?.close() },
                              onCopy: { [weak self] in self?.copy() },
                              onDone: { [weak self] in self?.done() })
        let host = FirstMouseHostingView(rootView: view)
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        host.frame = background.bounds
        background.addSubview(host)

        panel.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
        panel.onCancel = { [weak self] in self?.close() }
    }

    static func windowSize(for pointSize: CGSize, on screen: NSScreen?) -> CGSize {
        let visible = (screen ?? NSScreen.containingMouse() ?? NSScreen.main)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let maxCanvas = CGSize(width: visible.width * 0.78 - 44, height: visible.height * 0.78 - toolbarHeight - 44)
        let scale = min(1, maxCanvas.width / max(pointSize.width, 1), maxCanvas.height / max(pointSize.height, 1))
        return CGSize(width: max(680, ceil(pointSize.width * scale) + 44),
                      height: max(380, ceil(pointSize.height * scale) + 44 + toolbarHeight + 1))
    }

    private func show(on screen: NSScreen?) {
        let size = Self.windowSize(for: doc.fullRect.size, on: screen)
        let visible = (screen ?? NSScreen.containingMouse() ?? NSScreen.main)?.visibleFrame ?? .zero
        let frame = NSRect(x: round(visible.midX - size.width / 2), y: round(visible.midY - size.height / 2),
                           width: size.width, height: size.height)
        panel.setFrame(frame, display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    private func copy() {
        guard let png = doc.renderPNG() else { return }
        PasteboardWriter.writeImage(png: png, origin: PasteboardOrigin.screenshotName)
        doc.flashCopied()
    }

    private func done() {
        if let png = doc.renderPNG() {
            PasteboardWriter.writeImage(png: png, origin: PasteboardOrigin.screenshotName)
        }
        close()
    }

    private func close() {
        let panel = self.panel
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                EditorController.openEditors.removeAll { $0 === self }
            }
        })
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags.contains(.command) {
            switch key {
            case "z": flags.contains(.shift) ? doc.redo() : doc.undo(); return true
            case "c": copy(); return true
            case "w": close(); return true
            default: return false
            }
        }
        switch event.keyCode {
        case KeyCode.return, KeyCode.enter: done(); return true
        default: break
        }
        switch key {
        case "c": doc.tool = .crop; return true
        case "p", "s": doc.tool = .pen; return true
        default: return false
        }
    }
}

struct EditorView: View {
    @ObservedObject var doc: EditorDocument
    let onCancel: () -> Void
    let onCopy: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(doc: doc, onCancel: onCancel, onCopy: onCopy, onDone: onDone)
            Divider().opacity(0.6)
            EditorCanvas(doc: doc)
                .background(Color.primary.opacity(0.04))
        }
        .overlay(
            RoundedRectangle(cornerRadius: EditorController.cornerRadius, style: .circular)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 0.5)
        )
    }
}

struct EditorToolbar: View {
    @ObservedObject var doc: EditorDocument
    let onCancel: () -> Void
    let onCopy: () -> Void
    let onDone: () -> Void

    private var drawingEnabled: Bool { doc.tool == .pen }

    var body: some View {
        HStack(spacing: 0) {
            IconButton(symbol: "xmark", help: "Close without copying (esc)", action: onCancel)
            Spacer(minLength: 10)
            HStack(spacing: 12) {
                toolPicker
                separator
                palette
                    .opacity(drawingEnabled ? 1 : 0.3)
                    .allowsHitTesting(drawingEnabled)
                separator
                widths
                    .opacity(drawingEnabled ? 1 : 0.3)
                    .allowsHitTesting(drawingEnabled)
                separator
                HStack(spacing: 2) {
                    IconButton(symbol: "arrow.uturn.backward", help: "Undo (⌘Z)") { doc.undo() }
                        .opacity(doc.canUndo ? 1 : 0.35)
                        .allowsHitTesting(doc.canUndo)
                    IconButton(symbol: "arrow.uturn.forward", help: "Redo (⇧⌘Z)") { doc.redo() }
                        .opacity(doc.canRedo ? 1 : 0.35)
                        .allowsHitTesting(doc.canRedo)
                }
            }
            Spacer(minLength: 10)
            HStack(spacing: 8) {
                copyButton
                doneButton
            }
        }
        .padding(.horizontal, 12)
        .frame(height: EditorController.toolbarHeight)
        .background(WindowDragArea())
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 18)
    }

    private var toolPicker: some View {
        HStack(spacing: 2) {
            ToolToggle(symbol: "crop", selected: doc.tool == .crop, help: "Crop (C)") {
                doc.tool = .crop
            }
            ToolToggle(symbol: "paintbrush.pointed", selected: doc.tool == .pen, help: "Brush (P)") {
                doc.tool = .pen
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    private var palette: some View {
        HStack(spacing: 3) {
            ForEach(EditorPalette.colors.indices, id: \.self) { index in
                ColorSwatch(color: EditorPalette.colors[index], selected: doc.colorIndex == index) {
                    doc.colorIndex = index
                }
            }
        }
    }

    private var widths: some View {
        HStack(spacing: 2) {
            ForEach(EditorPalette.widths.indices, id: \.self) { index in
                Button { doc.widthIndex = index } label: {
                    Circle()
                        .fill(Color(nsColor: doc.color == .white ? .secondaryLabelColor : doc.color))
                        .frame(width: [4, 7, 11][index], height: [4, 7, 11][index])
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(doc.widthIndex == index ? 0.1 : 0))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(["Fine", "Medium", "Bold"][index])
            }
        }
    }

    private var copyButton: some View {
        Button(action: onCopy) {
            HStack(spacing: 5) {
                Image(systemName: doc.justCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11.5, weight: .semibold))
                Text(doc.justCopied ? "Copied" : "Copy")
                    .font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
            .contentShape(Capsule())
            .animation(.easeOut(duration: 0.15), value: doc.justCopied)
        }
        .buttonStyle(PressableStyle())
        .help("Copy to clipboard (⌘C)")
    }

    private var doneButton: some View {
        Button(action: onDone) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help("Done – copy and close (↩)")
    }
}

private struct ToolToggle: View {
    let symbol: String
    let selected: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .frame(width: 30, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(selected ? Color.accentColor : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .animation(.easeOut(duration: 0.12), value: selected)
    }
}

private struct ColorSwatch: View {
    let color: NSColor
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(nsColor: color))
                .frame(width: 15, height: 15)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
                .padding(3)
                .overlay(
                    Circle().strokeBorder(selected ? Color.primary.opacity(0.7) : Color.clear, lineWidth: 1.5)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}
