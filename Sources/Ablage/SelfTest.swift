import AppKit
import SwiftUI

/// `Ablage --selftest` opens the real panel with sample data and checks sizing and scrolling.
@MainActor
enum SelfTest {
    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--selftest") else { return false }
        editorTests()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ablage-selftest-\(UUID().uuidString)")
        let store = ClipboardStore(directory: dir)
        DesignSnapshot.seed(store)
        for i in 1...14 {
            var item = ClipItem(kind: .text, text: "Testeintrag Nummer \(i) mit etwas Text", sourceName: "Test")
            item.date = Date().addingTimeInterval(-Double(3000 + i * 60))
            store.addPrepared(item)
        }
        let controller = StatusBarController(clipboard: store, capture: CaptureController())
        pump(0.6)

        controller.showPanel()
        pump(0.6)
        print("home panel frame:", controller.panel.frame)

        controller.model.showClipboard()
        pump(1.0)
        print("clipboard panel frame:", controller.panel.frame)

        guard let scroll = findScrollView(in: controller.panel.contentView!) else {
            print("FAIL: no NSScrollView found"); return true
        }
        let inWindow = scroll.convert(scroll.bounds, to: nil)
        print("scroll view frame in window:", inWindow)
        let visibleOK = inWindow.minY >= -0.5 && inWindow.maxY <= controller.panel.frame.height + 0.5
        print(visibleOK ? "PASS: list fully inside panel" : "FAIL: list clipped by panel")
        print("document height:", scroll.documentView?.frame.height ?? -1, "clip height:", scroll.contentView.bounds.height)
        print("clip origin before:", scroll.contentView.bounds.origin)

        let probe = NSPoint(x: inWindow.midX, y: inWindow.midY)
        let hit = controller.panel.contentView?.superview?.hitTest(probe) ?? controller.panel.contentView?.hitTest(probe)
        print("hit view:", hit.map { String(describing: type(of: $0)) } ?? "nil",
              "inside scroll view:", hit?.isDescendant(of: scroll) ?? false)

        // Synthesised trackpad-style scroll aimed at the middle of the list.
        let screenPoint = controller.panel.convertPoint(toScreen: probe)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        if let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -120, wheel2: 0, wheel3: 0) {
            cg.location = CGPoint(x: screenPoint.x, y: primaryHeight - screenPoint.y)
            if let event = NSEvent(cgEvent: cg) {
                let start = Date()
                for _ in 0..<5 { controller.panel.sendEvent(event); pump(0.05) }
                print(String(format: "5 scroll events handled in %.0f ms", Date().timeIntervalSince(start) * 1000))
                print("event window:", event.window == nil ? "nil" : "set")
                scroll.scrollWheel(with: event)
                pump(0.3)
            }
        }
        print("clip origin after:", scroll.contentView.bounds.origin)
        print(scroll.contentView.bounds.origin.y > 0 ? "PASS: list scrolls" : "FAIL: list did not scroll")
        controller.model.showHome()
        pump(0.6)
        print("back to home frame:", controller.panel.frame)
        controller.closePanel(animated: false)
        try? FileManager.default.removeItem(at: dir)
        return true
    }

    private static func check(_ ok: Bool, _ label: String) {
        print(ok ? "PASS: \(label)" : "FAIL: \(label)")
    }

    /// Drives the real editor canvas with synthetic mouse events.
    private static func editorTests() {
        guard let image = DesignSnapshot.sampleCGImage(width: 400, height: 300) else {
            check(false, "sample image"); return
        }
        let doc = EditorDocument(image: image, pointSize: CGSize(width: 400, height: 300))
        let canvas = EditorCanvasView(doc: doc)
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 444, height: 344),
                              styleMask: .borderless, backing: .buffered, defer: false)
        canvas.frame = NSRect(x: 0, y: 0, width: 444, height: 344)
        window.contentView = canvas
        window.orderFrontRegardless()

        func send(_ type: NSEvent.EventType, _ point: CGPoint) {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                                 windowNumber: window.windowNumber, context: nil,
                                                 eventNumber: 0, clickCount: 1, pressure: 1) else { return }
            switch type {
            case .leftMouseDown: canvas.mouseDown(with: event)
            case .leftMouseDragged: canvas.mouseDragged(with: event)
            default: canvas.mouseUp(with: event)
            }
        }
        func drag(from a: CGPoint, to b: CGPoint) {
            send(.leftMouseDown, a)
            for step in 1...10 {
                let t = CGFloat(step) / 10
                send(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
            send(.leftMouseUp, b)
        }

        // Pen
        doc.tool = .pen
        drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200))
        check(doc.strokes.count == 1 && (doc.strokes.first?.points.count ?? 0) > 5, "pen draws a stroke")

        // Crop: canvas shows the image 1:1 inside 22 pt padding.
        doc.tool = .crop
        drag(from: CGPoint(x: 72, y: 72), to: CGPoint(x: 272, y: 172)) // image (50,50)-(250,150)
        let crop = doc.crop ?? .zero
        check(abs(crop.minX - 50) < 1 && abs(crop.width - 200) < 1 && abs(crop.height - 100) < 1,
              "crop frame drawn on image (got \(crop))")

        // Resize from the top-right corner.
        drag(from: CGPoint(x: 272, y: 172), to: CGPoint(x: 322, y: 222))
        let resized = doc.crop ?? .zero
        check(abs(resized.width - 250) < 1.5 && abs(resized.height - 150) < 1.5,
              "crop corner resizes (got \(resized.size))")

        // Rendered output: cropped size at 2x, with the stroke baked in.
        let rendered = doc.renderImage()
        check(rendered?.width == 500 && rendered?.height == 300,
              "render uses crop at Retina size (got \(rendered?.width ?? 0)×\(rendered?.height ?? 0))")

        doc.undo(); doc.undo()
        check(doc.crop == nil && doc.strokes.count == 1, "undo restores the uncropped image")
        doc.undo()
        check(doc.strokes.isEmpty && !doc.canUndo, "undo removes the stroke")
        doc.redo()
        check(doc.strokes.count == 1 && doc.canRedo, "redo brings the stroke back")
        check(doc.renderImage()?.width == 800, "uncropped render keeps full size")
        window.orderOut(nil)
    }

    private static func pump(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private static func findScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for sub in view.subviews { if let found = findScrollView(in: sub) { return found } }
        return nil
    }
}
