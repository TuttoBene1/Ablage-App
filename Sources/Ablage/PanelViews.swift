import AppKit
import SwiftUI

enum PanelMetrics {
    static let width: CGFloat = 330
    static let clipboardHeight: CGFloat = 468
}

// MARK: - Root

/// The panel window itself is sized by `StatusBarController` per route;
/// the content stays pinned to the top while the window animates.
struct PanelRootView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var store: ClipboardStore

    var body: some View {
        ZStack(alignment: .top) {
            if model.route == .home {
                HomeView(model: model, store: store)
                    .transition(.opacity)
            } else {
                ClipboardView(model: model, store: store)
                    .transition(.opacity)
            }
        }
        .frame(width: PanelMetrics.width)
        .fixedSize(horizontal: true, vertical: true)
        .animation(.easeOut(duration: 0.16), value: model.route)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(
            RoundedRectangle(cornerRadius: Chrome.panelRadius, style: .circular)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 0.5)
        )
    }
}

// MARK: - Home

struct HomeView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var store: ClipboardStore

    private var countText: String {
        let count = store.items.count
        if count == 0 { return "Leer" }
        return count == 1 ? "1 Eintrag" : "\(count) Einträge"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ActionTile(symbol: "camera.viewfinder",
                           title: "Bildschirmfoto",
                           subtitle: "Foto oder Video") {
                    model.onScreenshot?()
                }
                ActionTile(symbol: "list.clipboard",
                           title: "Zwischenablage",
                           subtitle: countText,
                           showsChevron: true) {
                    model.showClipboard()
                }
            }
            .padding(10)

            Divider().padding(.horizontal, 16).opacity(0.6)

            HStack {
                Button { NSWorkspace.shared.open(AppInfo.website) } label: {
                    Text("Ablage · by Webforging")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("webforging.de öffnen")
                Spacer()
                Menu {
                    Toggle("Beim Anmelden öffnen", isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.launchAtLogin = $0 }
                    ))
                    Divider()
                    Button("Über Ablage") {
                        model.onClose?()
                        AppInfo.showAbout()
                    }
                    Button("Ablage auf GitHub") { NSWorkspace.shared.open(AppInfo.repository) }
                    Divider()
                    Button("Ablage beenden") { model.onQuit?() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13, weight: .regular))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.secondary)
                .help("Optionen")
            }
            .padding(.horizontal, 16)
            .frame(height: 34)
        }
    }
}

struct ActionTile: View {
    let symbol: String
    let title: String
    let subtitle: String
    var showsChevron = false
    let action: () -> Void

    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    ZStack {
                        Circle().fill(Color.accentColor)
                        Image(systemName: symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 32, height: 32)
                    Spacer()
                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 3)
                    }
                }
                Spacer(minLength: 14)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 106, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(hover.on ? 0.09 : 0.05))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .onHover { hover.on = $0 }
        .animation(.easeOut(duration: 0.12), value: hover.on)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct IconButton: View {
    let symbol: String
    var help: String = ""
    let action: () -> Void
    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(hover.on ? 0.08 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
        .help(help)
    }
}

// MARK: - Clipboard

struct ClipboardView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var store: ClipboardStore
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            Divider().opacity(0.6)
            content
        }
        .frame(height: PanelMetrics.clipboardHeight)
        .onAppear {
            DispatchQueue.main.async { searchFocused = true }
        }
        .onChange(of: model.focusSearchTick) {
            searchFocused = true
        }
    }

    private var header: some View {
        ZStack {
            Text("Zwischenablage")
                .font(.system(size: 13, weight: .semibold))
            HStack {
                IconButton(symbol: "chevron.left", help: "Zurück") { model.showHome() }
                Spacer()
                Menu {
                    Button("Verlauf leeren") { store.clearHistory() }
                        .disabled(!store.items.contains { !$0.pinned })
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.secondary)
                .padding(.trailing, 6)
                .help("Optionen")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 42)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Suchen", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    @ViewBuilder
    private var content: some View {
        let pinned = model.pinnedItems
        let recent = model.recentItems
        if pinned.isEmpty && recent.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        if !pinned.isEmpty {
                            SectionLabel(title: "Angeheftet")
                            ForEach(pinned) { row($0) }
                        }
                        if !recent.isEmpty {
                            SectionLabel(title: "Verlauf")
                            ForEach(recent) { row($0) }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .onChange(of: model.keyboardScrollTick) {
                    guard let id = model.highlightedID else { return }
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) }
                }
            }
        }
    }

    private func row(_ item: ClipItem) -> some View {
        ClipRow(item: item,
                store: store,
                highlighted: model.highlightedID == item.id,
                copied: model.copiedID == item.id,
                onCopy: { model.copy(item) },
                onPin: { withAnimation(.easeOut(duration: 0.2)) { store.togglePin(item.id) } },
                onDelete: { withAnimation(.easeOut(duration: 0.2)) { model.delete(item.id) } },
                onHover: { model.hover(item.id) })
            .id(item.id)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: model.query.isEmpty ? "list.clipboard" : "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(model.query.isEmpty ? "Noch nichts kopiert" : "Keine Treffer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            if model.query.isEmpty {
                Text("Kopierte Texte, Bilder und Dateien\nerscheinen hier.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

struct SectionLabel: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}

struct ClipRow: View {
    let item: ClipItem
    let store: ClipboardStore
    let highlighted: Bool
    let copied: Bool
    let onCopy: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void
    let onHover: () -> Void

    @StateObject private var hover = HoverState()

    var body: some View {
        HStack(spacing: 10) {
            leading
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(item.kind == .text ? 2 : 1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
                .frame(width: 24, height: 24)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(highlighted ? 0.08 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onCopy)
        .onHover { inside in
            hover.on = inside
            if inside { onHover() }
        }
        .contextMenu {
            Button("Kopieren", action: onCopy)
            Button(item.pinned ? "Lösen" : "Anheften", action: onPin)
            if item.kind == .files, let url = item.fileURLs.first {
                Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            Divider()
            Button("Löschen", action: onDelete)
        }
    }

    @ViewBuilder
    private var leading: some View {
        switch item.kind {
        case .image:
            if let thumb = store.thumbnail(for: item) {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
            } else {
                SymbolBadge(symbol: "photo")
            }
        case .files:
            Image(nsImage: store.fileIcon(for: item))
                .resizable()
                .frame(width: 28, height: 28)
        case .text:
            if let icon = store.appIcon(for: item.sourceBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 26, height: 26)
            } else {
                SymbolBadge(symbol: "text.alignleft")
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if copied {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))
        } else if item.pinned || hover.on || highlighted {
            Button(action: onPin) {
                Image(systemName: item.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(item.pinned ? Color.accentColor : Color.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(item.pinned ? "Lösen" : "Anheften")
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if item.kind == .image, let w = item.pixelWidth, let h = item.pixelHeight {
            parts.append("\(w) × \(h)")
        }
        if let source = item.sourceName,
           source != PasteboardOrigin.screenshotName,
           source != PasteboardOrigin.recordingName {
            parts.append(source)
        }
        parts.append(RelativeTime.string(for: item.date))
        return parts.joined(separator: " · ")
    }
}

struct SymbolBadge: View {
    let symbol: String
    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.primary.opacity(0.07))
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            )
    }
}

enum RelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.unitsStyle = .short
        return formatter
    }()

    static func string(for date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return "Gerade eben" }
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
