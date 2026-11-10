import AppKit
import Combine

struct EditorStroke {
    var points: [CGPoint] // image space: points, origin bottom-left
    var color: CGColor
    var width: CGFloat
}

enum EditorTool { case crop, pen }

enum EditorPalette {
    static let colors: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen,
        .systemBlue, .systemPurple, .black, .white,
    ]
    static let widths: [CGFloat] = [2.5, 5, 10]
}

@MainActor
final class EditorDocument: ObservableObject {
    let image: CGImage
    let fullRect: CGRect

    @Published private(set) var strokes: [EditorStroke] = []
    @Published private(set) var crop: CGRect?
    @Published var tool: EditorTool = .pen
    @Published var colorIndex = 0
    @Published var widthIndex = 1
    @Published var justCopied = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    private struct Snapshot {
        let strokes: [EditorStroke]
        let crop: CGRect?
    }
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var copiedReset: DispatchWorkItem?

    init(image: CGImage, pointSize: CGSize) {
        self.image = image
        self.fullRect = CGRect(origin: .zero, size: pointSize)
    }

    var color: NSColor { EditorPalette.colors[colorIndex] }
    var visibleRect: CGRect { crop ?? fullRect }

    func addStroke(_ stroke: EditorStroke) {
        pushUndo()
        strokes.append(stroke)
    }

    func setCropLive(_ rect: CGRect) {
        let clamped = rect.intersection(fullRect)
        crop = clamped.isNull || clamped.equalTo(fullRect) ? nil : clamped
    }

    func commitCrop(previous: CGRect?) {
        if let current = crop, current.width < 8 || current.height < 8 {
            crop = previous
            return
        }
        guard previous != crop else { return }
        undoStack.append(Snapshot(strokes: strokes, crop: previous))
        redoStack.removeAll()
        updateFlags()
    }

    func resetCrop() {
        guard crop != nil else { return }
        pushUndo()
        crop = nil
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(Snapshot(strokes: strokes, crop: crop))
        apply(last)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(Snapshot(strokes: strokes, crop: crop))
        apply(next)
    }

    func flashCopied() {
        copiedReset?.cancel()
        justCopied = true
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.justCopied = false }
        }
        copiedReset = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    private func pushUndo() {
        undoStack.append(Snapshot(strokes: strokes, crop: crop))
        redoStack.removeAll()
        updateFlags()
    }

    private func apply(_ snapshot: Snapshot) {
        strokes = snapshot.strokes
        crop = snapshot.crop
        updateFlags()
    }

    private func updateFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    func renderPNG() -> Data? {
        guard let output = renderImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: output)
        rep.size = visibleRect.size
        return rep.representation(using: .png, properties: [:])
    }

    func renderImage() -> CGImage? {
        let target = visibleRect
        let scale = CGFloat(image.width) / fullRect.width
        let width = max(1, Int((target.width * scale).rounded()))
        let height = max(1, Int((target.height * scale).rounded()))
        let space = image.colorSpace.flatMap { $0.supportsOutput ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ?? CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -target.minX, y: -target.minY)
        ctx.draw(image, in: fullRect)
        EditorRenderer.draw(strokes, in: ctx)
        return ctx.makeImage()
    }
}

enum EditorRenderer {
    static func path(for points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count < 3 {
            if points.count == 1 { path.addLine(to: first) }
            points.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }
        for index in 1..<(points.count - 1) {
            let current = points[index]
            let next = points[index + 1]
            let mid = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
            path.addQuadCurve(to: mid, control: current)
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    static func draw(_ strokes: [EditorStroke], in ctx: CGContext) {
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for stroke in strokes {
            ctx.addPath(path(for: stroke.points))
            ctx.setStrokeColor(stroke.color)
            ctx.setLineWidth(stroke.width)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }
}
