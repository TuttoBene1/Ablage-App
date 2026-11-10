import AppKit
import SwiftUI

final class PreviewModel: ObservableObject {
    @Published var visible = false
    @Published var hovering = false
}

@MainActor
final class ScreenshotPreview {
    static let shared = ScreenshotPreview()

    private static let shadowMargin: CGFloat = 26
    private static let edgeInset: CGFloat = 18
    private static let displayDuration: TimeInterval = 5

    private var panel: FloatingPanel?
    private var model: PreviewModel?
    private var hideWork: DispatchWorkItem?

    func show(image: CGImage, pointSize: CGSize, screen: NSScreen?, onOpen: @escaping () -> Void) {
        dismiss(animated: false)
        guard let target = screen ?? NSScreen.containingMouse() ?? NSScreen.main else { return }

        let visible = target.visibleFrame
        let card = Self.cardSize(for: pointSize)
        let margin = Self.shadowMargin
        let cardOrigin = CGPoint(x: visible.maxX - Self.edgeInset - card.width,
                                 y: visible.minY + Self.edgeInset)
        let frame = NSRect(x: cardOrigin.x - margin,
                           y: cardOrigin.y - margin,
                           width: visible.maxX - (cardOrigin.x - margin),
                           height: card.height + margin * 2)

        let model = PreviewModel()
        let view = PreviewCard(image: NSImage(cgImage: image, size: pointSize),
                               cardSize: card,
                               margin: margin,
                               slideDistance: frame.width,
                               model: model,
                               onOpen: { [weak self] in
                                   self?.dismiss(animated: true)
                                   onOpen()
                               },
                               onHover: { [weak self] inside in self?.hoverChanged(inside) })
        let host = FirstMouseHostingView(rootView: view)
        let panel = FloatingPanel(contentRect: frame)
        panel.level = .statusBar
        panel.hasShadow = false
        panel.contentView = host
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()

        self.panel = panel
        self.model = model
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { model.visible = true }
        }
        scheduleHide(after: Self.displayDuration)
    }

    func dismiss(animated: Bool) {
        hideWork?.cancel()
        guard let panel, let model else { return }
        self.panel = nil
        self.model = nil
        guard animated else { panel.orderOut(nil); return }
        withAnimation(.easeIn(duration: 0.28)) { model.visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { panel.orderOut(nil) }
    }

    private func hoverChanged(_ inside: Bool) {
        guard let model else { return }
        withAnimation(.easeOut(duration: 0.15)) { model.hovering = inside }
        if inside {
            hideWork?.cancel()
        } else {
            scheduleHide(after: 2.5)
        }
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.dismiss(animated: true) }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    static func cardSize(for size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: 180, height: 110) }
        let scale = min(200 / size.width, 128 / size.height)
        return CGSize(width: max(56, (size.width * scale).rounded()),
                      height: max(44, (size.height * scale).rounded()))
    }
}

struct PreviewCard: View {
    let image: NSImage
    let cardSize: CGSize
    let margin: CGFloat
    let slideDistance: CGFloat
    @ObservedObject var model: PreviewModel
    let onOpen: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            card
                .padding(margin)
                .offset(x: model.visible ? 0 : slideDistance)
                .opacity(model.visible ? 1 : 0.4)
        }
    }

    private var card: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: cardSize.width, height: cardSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.38))
                    Label("Edit", systemImage: "paintbrush.pointed.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .opacity(model.hovering ? 1 : 0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.5)
            )
            .background(
                RoundedRectangle(cornerRadius: 10.5, style: .continuous)
                    .fill(Color.black.opacity(0.12))
                    .padding(-0.5)
            )
            .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
            .scaleEffect(model.hovering ? 1.03 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onHover(perform: onHover)
            .onTapGesture(perform: onOpen)
            .help("Click to edit")
    }
}
