import AppKit
import SwiftUI

@MainActor
enum DesignSnapshot {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count else { return false }
        render(to: URL(fileURLWithPath: args[index + 1]))
        return true
    }

    private static func render(to folder: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let dataDir = folder.appendingPathComponent("sample-data")
        try? fm.removeItem(at: dataDir)
        let store = ClipboardStore(directory: dataDir)
        seed(store)
        let model = PanelModel(store: store, shortcuts: ShortcutSettings(defaults: UserDefaults(suiteName: "ablage-snapshot")!, hotKeys: nil))

        for (name, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            let appearance = NSAppearance(named: appearanceName)!
            model.reset()
            write(panel(model: model, store: store, appearance: appearance, height: 156),
                  to: folder.appendingPathComponent("home-\(name).png"))
            model.showClipboard()
            model.highlightedID = model.visibleItems.dropFirst(2).first?.id
            write(panel(model: model, store: store, appearance: appearance, height: PanelMetrics.clipboardHeight),
                  to: folder.appendingPathComponent("clipboard-\(name).png"))
            model.showShortcut()
            write(panel(model: model, store: store, appearance: appearance, height: PanelMetrics.shortcutHeight),
                  to: folder.appendingPathComponent("shortcut-\(name).png"))

            let toast = ToastView(image: sampleImage(width: 320, height: 200), symbol: nil,
                                  title: "Screenshot copied", subtitle: "Press ⌘V to paste",
                                  tappable: false, onTap: {})
            write(render(toast, appearance: appearance, background: backdrop(appearance), radius: ToastView.radius),
                  to: folder.appendingPathComponent("toast-\(name).png"))

            let doc = sampleEditorDocument()
            let size = EditorController.windowSize(for: doc.fullRect.size, on: NSScreen.main)
            let editorBackground = appearance.name == .darkAqua
                ? NSColor(calibratedWhite: 0.19, alpha: 1) : NSColor(calibratedWhite: 0.93, alpha: 1)
            write(render(EditorView(doc: doc, onCancel: {}, onCopy: {}, onDone: {})
                            .frame(width: size.width, height: size.height),
                         appearance: appearance, background: editorBackground,
                         radius: EditorController.cornerRadius, size: size),
                  to: folder.appendingPathComponent("editor-\(name).png"))
            doc.tool = .crop
            doc.setCropLive(CGRect(x: 160, y: 110, width: 560, height: 330))
            doc.commitCrop(previous: nil)
            write(render(EditorView(doc: doc, onCancel: {}, onCopy: {}, onDone: {})
                            .frame(width: size.width, height: size.height),
                         appearance: appearance, background: editorBackground,
                         radius: EditorController.cornerRadius, size: size),
                  to: folder.appendingPathComponent("editor-crop-\(name).png"))
            if name == "light", let png = doc.renderPNG() {
                try? png.write(to: folder.appendingPathComponent("editor-result.png"))
            }
        }

        if let image = sampleCGImage(width: 900, height: 560) {
            for hovering in [false, true] {
                let model = PreviewModel()
                model.visible = true
                model.hovering = hovering
                let card = ScreenshotPreview.cardSize(for: CGSize(width: 900, height: 560))
                let view = PreviewCard(image: NSImage(cgImage: image, size: CGSize(width: 900, height: 560)),
                                       cardSize: card, margin: 26, slideDistance: 0, model: model,
                                       onOpen: {}, onHover: { _ in })
                    .frame(width: card.width + 52, height: card.height + 52)
                write(render(view, appearance: NSAppearance(named: .aqua)!,
                             background: NSColor(calibratedRed: 0.42, green: 0.5, blue: 0.62, alpha: 1), radius: 0,
                             size: CGSize(width: card.width + 52, height: card.height + 52)),
                      to: folder.appendingPathComponent(hovering ? "preview-hover.png" : "preview.png"))
            }
        }

        let capture = CaptureController()
        write(render(CaptureToolbar(controller: capture),
                     appearance: NSAppearance(named: .darkAqua)!,
                     background: NSColor(calibratedRed: 0.32, green: 0.36, blue: 0.42, alpha: 1), radius: 0),
              to: folder.appendingPathComponent("toolbar-photo.png"))
        capture.mode = .video
        write(render(CaptureToolbar(controller: capture),
                     appearance: NSAppearance(named: .darkAqua)!,
                     background: NSColor(calibratedRed: 0.32, green: 0.36, blue: 0.42, alpha: 1), radius: 0),
              to: folder.appendingPathComponent("toolbar-video.png"))
        print("Snapshots written to \(folder.path)")
    }

    static func sampleEditorDocument() -> EditorDocument {
        let doc = EditorDocument(image: sampleCGImage(width: 900, height: 560)!,
                                 pointSize: CGSize(width: 900, height: 560))
        var ring: [CGPoint] = []
        for step in 0...40 {
            let angle = Double(step) / 40 * 2 * .pi * 1.05
            ring.append(CGPoint(x: 610 + cos(angle) * 120, y: 330 + sin(angle) * 55))
        }
        doc.addStroke(EditorStroke(points: ring, color: NSColor.systemRed.cgColor, width: 5))
        doc.addStroke(EditorStroke(points: [CGPoint(x: 250, y: 200), CGPoint(x: 330, y: 204), CGPoint(x: 420, y: 199)],
                                   color: NSColor.systemBlue.cgColor, width: 4))
        return doc
    }

    static func sampleCGImage(width: CGFloat, height: CGFloat) -> CGImage? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: Int(height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        NSGradient(colors: [NSColor.systemIndigo, NSColor.systemTeal])?.draw(in: rect, angle: 35)
        let window = rect.insetBy(dx: width * 0.12, dy: height * 0.12)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: window, xRadius: 14, yRadius: 14).fill()
        NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: window.minX, y: window.maxY - 44, width: window.width, height: 30)).fill()
        NSBezierPath(roundedRect: NSRect(x: window.minX, y: window.maxY - 44, width: window.width, height: 44),
                     xRadius: 14, yRadius: 14).fill()
        for (index, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: window.minX + 16 + CGFloat(index) * 20, y: window.maxY - 28, width: 12, height: 12)).fill()
        }
        NSColor(calibratedWhite: 0.82, alpha: 1).setFill()
        for line in 0..<7 {
            let w = window.width * [0.62, 0.8, 0.7, 0.45, 0.76, 0.58, 0.68][line]
            NSBezierPath(roundedRect: NSRect(x: window.minX + 32, y: window.maxY - 90 - CGFloat(line) * 36,
                                             width: w, height: 12), xRadius: 6, yRadius: 6).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }

    private static func backdrop(_ appearance: NSAppearance) -> NSColor {
        appearance.name == .darkAqua
            ? NSColor(calibratedWhite: 0.16, alpha: 1)
            : NSColor(calibratedWhite: 0.955, alpha: 1)
    }

    private static func panel(model: PanelModel, store: ClipboardStore, appearance: NSAppearance, height: CGFloat) -> NSBitmapImageRep? {
        let root = PanelRootView(model: model, store: store)
            .frame(width: PanelMetrics.width, height: height)
        return render(root, appearance: appearance, background: backdrop(appearance), radius: Chrome.panelRadius,
                      size: NSSize(width: PanelMetrics.width, height: height))
    }

    private static func render<V: View>(_ view: V, appearance: NSAppearance, background: NSColor,
                                        radius: CGFloat, size: NSSize? = nil) -> NSBitmapImageRep? {
        let host = NSHostingView(rootView: view)
        host.appearance = appearance
        let finalSize = size ?? host.fittingSize
        let container = NSView(frame: NSRect(origin: .zero, size: finalSize))
        container.wantsLayer = true
        container.appearance = appearance
        container.layer?.backgroundColor = background.cgColor
        container.layer?.cornerRadius = radius
        container.layer?.masksToBounds = radius > 0
        host.frame = container.bounds
        container.addSubview(host)

        let window = NSWindow(contentRect: container.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = container
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderFrontRegardless()
        container.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        container.displayIfNeeded()

        guard let rep = container.bitmapImageRepForCachingDisplay(in: container.bounds) else { return nil }
        container.cacheDisplay(in: container.bounds, to: rep)
        window.orderOut(nil)
        return rep
    }

    private static func write(_ rep: NSBitmapImageRep?, to url: URL) {
        guard let data = rep?.representation(using: .png, properties: [:]) else {
            print("Could not render \(url.lastPathComponent)")
            return
        }
        try? data.write(to: url)
    }

    static func seed(_ store: ClipboardStore) {
        let now = Date()
        func text(_ value: String, _ app: String, _ bundle: String, minutesAgo: Double, pinned: Bool = false) -> ClipItem {
            var item = ClipItem(kind: .text, text: value, sourceBundleID: bundle, sourceName: app)
            item.date = now.addingTimeInterval(-minutesAgo * 60)
            item.pinned = pinned
            return item
        }
        store.addPrepared(text("Marienplatz 1, 80331 Munich", "Notes", "com.apple.Notes", minutesAgo: 60 * 26, pinned: true))
        store.addPrepared(text("See you at 2 pm at the café on the square – I’ll book a table for four.", "Messages", "com.apple.MobileSMS", minutesAgo: 60 * 50, pinned: true))
        store.addPrepared(text("https://developer.apple.com/design/human-interface-guidelines/", "Safari", "com.apple.Safari", minutesAgo: 0.3))
        store.addPrepared(text("git commit -m \"Polish sidebar layout\"", "Terminal", "com.apple.Terminal", minutesAgo: 12))
        store.addPrepared(text("Thanks for the quick reply! Attached is the revised version with the changes we discussed.", "Mail", "com.apple.mail", minutesAgo: 95))

        if let png = sampleImage(width: 2560, height: 1440).flatMap(pngData) {
            let file = UUID().uuidString + ".png"
            try? png.write(to: store.imagesDirectory.appendingPathComponent(file))
            var item = ClipItem(kind: .image, sourceName: PasteboardOrigin.screenshotName)
            item.imageFile = file
            item.pixelWidth = 2560
            item.pixelHeight = 1440
            item.date = now.addingTimeInterval(-4 * 60)
            store.addPrepared(item)
        }

        var file = ClipItem(kind: .files, filePaths: ["/Users/Shared/Q4 Presentation.key"], sourceBundleID: "com.apple.finder", sourceName: "Finder")
        file.date = now.addingTimeInterval(-40 * 60)
        store.addPrepared(file)
    }

    private static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func sampleImage(width: CGFloat, height: CGFloat) -> NSImage? {
        NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSGradient(colors: [NSColor.systemIndigo, NSColor.systemTeal])?.draw(in: rect, angle: 35)
            let card = rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.2)
            NSColor.white.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: card, xRadius: rect.height * 0.03, yRadius: rect.height * 0.03).fill()
            return true
        }
    }
}
