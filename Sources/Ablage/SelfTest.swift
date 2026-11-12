import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
enum SelfTest {
    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--selftest") else { return false }
        editorTests()
        shortcutTests()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ablage-selftest-\(UUID().uuidString)")
        let store = ClipboardStore(directory: dir)
        DesignSnapshot.seed(store)
        for i in 1...14 {
            var item = ClipItem(kind: .text, text: "Test item number \(i) with some text", sourceName: "Test")
            item.date = Date().addingTimeInterval(-Double(3000 + i * 60))
            store.addPrepared(item)
        }
        let shortcuts = ShortcutSettings(defaults: UserDefaults(suiteName: "ablage-selftest-panel")!, hotKeys: nil)
        let controller = StatusBarController(clipboard: store, capture: CaptureController(), shortcuts: shortcuts)
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

        doc.tool = .pen
        drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200))
        check(doc.strokes.count == 1 && (doc.strokes.first?.points.count ?? 0) > 5, "pen draws a stroke")

        doc.tool = .crop
        drag(from: CGPoint(x: 72, y: 72), to: CGPoint(x: 272, y: 172))
        let crop = doc.crop ?? .zero
        check(abs(crop.minX - 50) < 1 && abs(crop.width - 200) < 1 && abs(crop.height - 100) < 1,
              "crop frame drawn on image (got \(crop))")

        drag(from: CGPoint(x: 272, y: 172), to: CGPoint(x: 322, y: 222))
        let resized = doc.crop ?? .zero
        check(abs(resized.width - 250) < 1.5 && abs(resized.height - 150) < 1.5,
              "crop corner resizes (got \(resized.size))")

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

    private static func shortcutTests() {
        check(Shortcut.screenshotDefault.displayString == "⇧⌘2",
              "default shortcut reads ⇧⌘2 (got \(Shortcut.screenshotDefault.displayString))")
        check(!Shortcut.screenshotDefault.isUsedByMacOS, "⇧⌘2 is not a macOS shortcut")
        check(!Shortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(cmdKey)).isUsableGlobally, "⌘A alone is rejected")
        check(!Shortcut(keyCode: UInt32(kVK_ANSI_E), modifiers: UInt32(optionKey | shiftKey)).isUsableGlobally,
              "⌥⇧E is rejected (types characters)")
        check(Shortcut(keyCode: UInt32(kVK_F13), modifiers: 0).isUsableGlobally, "F13 alone is allowed")

        let suite = "ablage-selftest-shortcuts"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = ShortcutSettings(defaults: defaults, hotKeys: .shared)
        check(settings.screenshot == .screenshotDefault, "without a saved value the default is used")

        settings.startRecording()
        _ = settings.handle(keyEvent(kVK_ANSI_A, []))
        check(settings.isRecording && settings.message != nil, "a plain letter keeps recording and shows a hint")

        let areaShortcut = Shortcut(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(cmdKey | shiftKey))
        if areaShortcut.isUsedByMacOS {
            _ = settings.handle(keyEvent(kVK_ANSI_4, [.command, .shift]))
            check(settings.message?.contains("macOS") == true && settings.screenshot == .screenshotDefault,
                  "⇧⌘4 is refused while macOS uses it")
            settings.startRecording()
        }

        _ = settings.handle(keyEvent(kVK_F12, [.control, .option, .command]))
        check(!settings.isRecording && settings.screenshot?.displayString == "⌃⌥⌘F12" && settings.isAvailable,
              "⌃⌥⌘F12 is recorded and registered (got \(settings.screenshot?.displayString ?? "none"))")
        check(ShortcutSettings(defaults: defaults, hotKeys: nil).screenshot == settings.screenshot, "the shortcut is saved")

        var pressed = false
        HotKeyCenter.shared.onPress = { pressed = true }
        var event: EventRef?
        CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, EventAttributes(kEventAttributeNone), &event)
        if let event {
            SendEventToEventTarget(event, GetApplicationEventTarget())
            ReleaseEvent(event)
        }
        pump(0.2)
        check(pressed, "a hotkey press reaches the app")
        HotKeyCenter.shared.onPress = nil

        settings.clear()
        check(ShortcutSettings(defaults: defaults, hotKeys: nil).screenshot == nil, "a removed shortcut stays removed")
        HotKeyCenter.shared.unregister()
        defaults.removePersistentDomain(forName: suite)
    }

    private static func keyEvent(_ code: Int, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false,
                         keyCode: UInt16(code))!
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
