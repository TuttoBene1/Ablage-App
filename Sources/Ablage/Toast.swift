import AppKit
import SwiftUI

/// Small, self-dismissing confirmation bubble near the bottom of the screen.
@MainActor
final class Toast {
    static let shared = Toast()

    private var panel: FloatingPanel?
    private var hideWork: DispatchWorkItem?

    func show(image: NSImage? = nil,
              symbol: String? = nil,
              title: String,
              subtitle: String? = nil,
              on screen: NSScreen? = nil,
              duration: TimeInterval = 2,
              action: (() -> Void)? = nil) {
        hideWork?.cancel()
        panel?.orderOut(nil)

        let view = ToastView(image: image, symbol: symbol, title: title, subtitle: subtitle,
                             tappable: action != nil) { [weak self] in
            action?()
            self?.hide()
        }
        let host = FirstMouseHostingView(rootView: view)
        let size = host.fittingSize

        let panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: size))
        panel.level = .statusBar
        panel.ignoresMouseEvents = action == nil
        let background = Chrome.background(radius: ToastView.radius)
        panel.contentView = background
        host.frame = background.bounds
        host.autoresizingMask = [.width, .height]
        background.addSubview(host)

        let target = screen ?? NSScreen.containingMouse() ?? NSScreen.main
        let visible = target?.visibleFrame ?? .zero
        let finalFrame = NSRect(x: round(visible.midX - size.width / 2),
                                y: round(visible.minY + 56),
                                width: size.width, height: size.height)
        panel.setFrame(finalFrame.offsetBy(dx: 0, dy: -8), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
        }
        self.panel = panel

        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.hide() }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }
}

struct ToastView: View {
    static let radius: CGFloat = 16

    let image: NSImage?
    let symbol: String?
    let title: String
    let subtitle: String?
    let tappable: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
            } else if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: 260, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if tappable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .fixedSize()
        .contentShape(Rectangle())
        .onTapGesture { if tappable { onTap() } }
        .overlay(
            RoundedRectangle(cornerRadius: Self.radius, style: .circular)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 0.5)
        )
    }
}
