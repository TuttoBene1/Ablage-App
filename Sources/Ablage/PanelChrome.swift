import AppKit
import SwiftUI

/// Borderless, non-activating floating panel. It can become key (for the search
/// field and keyboard navigation) without stealing focus from the frontmost app,
/// so windows in screenshots keep their active look.
final class FloatingPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?
    var onCancel: (() -> Void)?

    init(contentRect: NSRect = .zero) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovable = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if let keyHandler, keyHandler(event) { return }
            if event.keyCode == 53 { onCancel?(); return } // esc, before the text field sees it
        }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// NSHostingView that reacts to the very first click, even in a non-key window.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

enum Chrome {
    static let panelRadius: CGFloat = 18

    /// Frosted background with real rounded corners (the blur itself is masked).
    static func background(radius: CGFloat, material: NSVisualEffectView.Material = .popover) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = roundedMask(radius: radius)
        return view
    }

    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 2
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }

    static func containingMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}

enum Sounds {
    private static let base = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/"

    static func play(_ file: String) {
        let path = base + file
        guard FileManager.default.fileExists(atPath: path),
              let sound = NSSound(contentsOfFile: path, byReference: true) else { return }
        sound.volume = 0.6
        sound.play()
    }

    static func shutter() { play("Screen Capture.aif") }
    static func beginRecording() { play("begin_record.caf") }
    static func endRecording() { play("end_record.caf") }
}

/// Hover flag for SwiftUI rows and buttons (works without the @State macro,
/// which needs a full Xcode install).
final class HoverState: ObservableObject {
    @Published var on = false
}
