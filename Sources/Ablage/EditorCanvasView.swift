import AppKit
import Combine
import SwiftUI

final class EditorCanvasView: NSView {
    private let doc: EditorDocument
    private var observer: AnyCancellable?
    private var currentStroke: EditorStroke?

    private struct Edges: OptionSet {
        let rawValue: Int
        static let left = Edges(rawValue: 1)
        static let right = Edges(rawValue: 2)
        static let top = Edges(rawValue: 4)
        static let bottom = Edges(rawValue: 8)
    }

    private enum CropDrag {
        case new(start: CGPoint)
        case move(anchor: CGPoint, start: CGRect)
        case resize(edges: Edges, start: CGRect)
    }

    private var cropDrag: CropDrag?
    private var cropBefore: CGRect?
    private static let padding: CGFloat = 22
    private static let minCrop: CGFloat = 10

    @MainActor
    init(doc: EditorDocument) {
        self.doc = doc
        super.init(frame: .zero)
        observer = doc.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.needsDisplay = true
                self.window?.invalidateCursorRects(for: self)
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var shownRect: CGRect { doc.tool == .crop ? doc.fullRect : doc.visibleRect }

    private var layoutInfo: (scale: CGFloat, frame: CGRect) {
        let area = bounds.insetBy(dx: Self.padding, dy: Self.padding)
        let shown = shownRect
        guard shown.width > 0, shown.height > 0, area.width > 0, area.height > 0 else { return (1, .zero) }
        let scale = min(area.width / shown.width, area.height / shown.height, 3)
        let size = CGSize(width: shown.width * scale, height: shown.height * scale)
        let frame = CGRect(x: (bounds.midX - size.width / 2).rounded(),
                           y: (bounds.midY - size.height / 2).rounded(),
                           width: size.width, height: size.height)
        return (scale, frame)
    }

    private func toView(_ point: CGPoint) -> CGPoint {
        let (scale, frame) = layoutInfo
        let shown = shownRect
        return CGPoint(x: frame.minX + (point.x - shown.minX) * scale,
                       y: frame.minY + (point.y - shown.minY) * scale)
    }

    private func toImage(_ point: CGPoint) -> CGPoint {
        let (scale, frame) = layoutInfo
        let shown = shownRect
        return CGPoint(x: shown.minX + (point.x - frame.minX) / scale,
                       y: shown.minY + (point.y - frame.minY) / scale)
    }

    private func toView(_ rect: CGRect) -> CGRect {
        let a = toView(CGPoint(x: rect.minX, y: rect.minY))
        let b = toView(CGPoint(x: rect.maxX, y: rect.maxY))
        return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }

    private func clampToImage(_ point: CGPoint) -> CGPoint {
        let full = doc.fullRect
        return CGPoint(x: min(max(point.x, full.minX), full.maxX), y: min(max(point.y, full.minY), full.maxY))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let (scale, frame) = layoutInfo
        let shown = shownRect

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 18,
                      color: NSColor.black.withAlphaComponent(0.22).cgColor)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(frame)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.clip(to: frame)
        ctx.translateBy(x: frame.minX - shown.minX * scale, y: frame.minY - shown.minY * scale)
        ctx.scaleBy(x: scale, y: scale)
        ctx.interpolationQuality = .high
        ctx.draw(doc.image, in: doc.fullRect)
        var strokes = doc.strokes
        if let currentStroke { strokes.append(currentStroke) }
        EditorRenderer.draw(strokes, in: ctx)
        ctx.restoreGState()

        if doc.tool == .crop { drawCropOverlay(in: ctx, imageFrame: frame) }
    }

    private func drawCropOverlay(in ctx: CGContext, imageFrame: CGRect) {
        let crop = toView(doc.visibleRect)
        ctx.saveGState()

        let dim = CGMutablePath()
        dim.addRect(imageFrame)
        dim.addRect(crop)
        ctx.addPath(dim)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        ctx.fillPath(using: .evenOdd)

        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
        ctx.setLineWidth(0.5)
        for i in 1...2 {
            let x = crop.minX + crop.width * CGFloat(i) / 3
            let y = crop.minY + crop.height * CGFloat(i) / 3
            ctx.move(to: CGPoint(x: x, y: crop.minY)); ctx.addLine(to: CGPoint(x: x, y: crop.maxY))
            ctx.move(to: CGPoint(x: crop.minX, y: y)); ctx.addLine(to: CGPoint(x: crop.maxX, y: y))
        }
        ctx.strokePath()

        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(crop.insetBy(dx: 0.5, dy: 0.5))

        let length = min(20, crop.width / 2 + 2, crop.height / 2 + 2)
        let inset: CGFloat = -2
        ctx.setLineWidth(4)
        ctx.setLineCap(.round)
        ctx.setShadow(offset: .zero, blur: 2, color: NSColor.black.withAlphaComponent(0.4).cgColor)
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: crop.minX + inset, y: crop.minY + inset), 1, 1),
            (CGPoint(x: crop.maxX - inset, y: crop.minY + inset), -1, 1),
            (CGPoint(x: crop.minX + inset, y: crop.maxY - inset), 1, -1),
            (CGPoint(x: crop.maxX - inset, y: crop.maxY - inset), -1, -1),
        ]
        for (corner, dx, dy) in corners {
            ctx.move(to: CGPoint(x: corner.x + dx * length, y: corner.y))
            ctx.addLine(to: corner)
            ctx.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * length))
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        let point = convert(event.locationInWindow, from: nil)
        MainActor.assumeIsolated {
            switch doc.tool {
            case .pen:
                let width = EditorPalette.widths[doc.widthIndex] / layoutInfo.scale
                currentStroke = EditorStroke(points: [toImage(point)], color: doc.color.cgColor, width: width)
                needsDisplay = true
            case .crop:
                cropBefore = doc.crop
                let crop = toView(doc.visibleRect)
                if let edges = edges(at: point, crop: crop) {
                    cropDrag = .resize(edges: edges, start: doc.visibleRect)
                } else if doc.crop != nil, crop.contains(point) {
                    cropDrag = .move(anchor: toImage(point), start: doc.visibleRect)
                    NSCursor.closedHand.set()
                } else {
                    cropDrag = .new(start: clampToImage(toImage(point)))
                }
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        MainActor.assumeIsolated {
            switch doc.tool {
            case .pen:
                guard var stroke = currentStroke else { return }
                let imagePoint = toImage(point)
                if let last = stroke.points.last,
                   hypot(imagePoint.x - last.x, imagePoint.y - last.y) * layoutInfo.scale < 1 { return }
                stroke.points.append(imagePoint)
                currentStroke = stroke
                needsDisplay = true
            case .crop:
                guard let drag = cropDrag else { return }
                let current = clampToImage(toImage(point))
                doc.setCropLive(updatedCrop(for: drag, current: current, raw: toImage(point)))
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        MainActor.assumeIsolated {
            switch doc.tool {
            case .pen:
                if let stroke = currentStroke { doc.addStroke(stroke) }
                currentStroke = nil
                needsDisplay = true
            case .crop:
                if cropDrag != nil { doc.commitCrop(previous: cropBefore) }
                cropDrag = nil
                updateCursor(at: convert(event.locationInWindow, from: nil))
            }
        }
    }

    @MainActor
    private func updatedCrop(for drag: CropDrag, current: CGPoint, raw: CGPoint) -> CGRect {
        let full = doc.fullRect
        let minSize = Self.minCrop
        switch drag {
        case .new(let start):
            return CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                          width: abs(current.x - start.x), height: abs(current.y - start.y))
        case .move(let anchor, let start):
            var rect = start.offsetBy(dx: raw.x - anchor.x, dy: raw.y - anchor.y)
            rect.origin.x = min(max(rect.minX, full.minX), full.maxX - rect.width)
            rect.origin.y = min(max(rect.minY, full.minY), full.maxY - rect.height)
            return rect
        case .resize(let edges, let start):
            var minX = start.minX, maxX = start.maxX, minY = start.minY, maxY = start.maxY
            if edges.contains(.left) { minX = min(current.x, maxX - minSize) }
            if edges.contains(.right) { maxX = max(current.x, minX + minSize) }
            if edges.contains(.bottom) { minY = min(current.y, maxY - minSize) }
            if edges.contains(.top) { maxY = max(current.y, minY + minSize) }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }

    private func edges(at point: CGPoint, crop: CGRect) -> Edges? {
        let tolerance: CGFloat = 10
        guard crop.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { return nil }
        var edges: Edges = []
        if abs(point.x - crop.minX) <= tolerance { edges.insert(.left) }
        if abs(point.x - crop.maxX) <= tolerance { edges.insert(.right) }
        if abs(point.y - crop.minY) <= tolerance { edges.insert(.bottom) }
        if abs(point.y - crop.maxY) <= tolerance { edges.insert(.top) }
        if edges.contains(.left) && edges.contains(.right) { edges.remove(.right) }
        if edges.contains(.top) && edges.contains(.bottom) { edges.remove(.bottom) }
        return edges.isEmpty ? nil : edges
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor(at: convert(event.locationInWindow, from: nil)) }
    override func mouseMoved(with event: NSEvent) { updateCursor(at: convert(event.locationInWindow, from: nil)) }

    private func updateCursor(at point: CGPoint) {
        MainActor.assumeIsolated {
            guard doc.tool == .crop else { NSCursor.crosshair.set(); return }
            let crop = toView(doc.visibleRect)
            if let edges = edges(at: point, crop: crop) {
                Self.resizeCursor(for: edges).set()
            } else if doc.crop != nil, crop.contains(point) {
                NSCursor.openHand.set()
            } else {
                NSCursor.crosshair.set()
            }
        }
    }

    private static func resizeCursor(for edges: Edges) -> NSCursor {
        let position: NSCursor.FrameResizePosition
        switch (edges.contains(.left), edges.contains(.right), edges.contains(.top), edges.contains(.bottom)) {
        case (true, _, true, _): position = .topLeft
        case (true, _, _, true): position = .bottomLeft
        case (_, true, true, _): position = .topRight
        case (_, true, _, true): position = .bottomRight
        case (true, _, _, _): position = .left
        case (_, true, _, _): position = .right
        case (_, _, true, _): position = .top
        default: position = .bottom
        }
        return NSCursor.frameResize(position: position, directions: .all)
    }
}

struct EditorCanvas: NSViewRepresentable {
    let doc: EditorDocument

    func makeNSView(context: Context) -> EditorCanvasView { EditorCanvasView(doc: doc) }
    func updateNSView(_ nsView: EditorCanvasView, context: Context) { nsView.needsDisplay = true }
}
