import AppKit
import SwiftUI

struct ShortcutView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var settings: ShortcutSettings

    private var status: (text: String, isError: Bool)? {
        if settings.isRecording { return ("Press the new shortcut. esc cancels, ⌫ removes it.", false) }
        if let message = settings.message { return (message, true) }
        if !settings.isAvailable, let shortcut = settings.screenshot {
            return ("\(shortcut.displayString) is used by another app – choose a different one.", true)
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Keyboard Shortcut")
                    .font(.system(size: 13, weight: .semibold))
                HStack {
                    IconButton(symbol: "chevron.left", help: "Back") { model.showHome() }
                    Spacer()
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 42)

            Divider().opacity(0.6)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Take Screenshot")
                            .font(.system(size: 13, weight: .medium))
                        Text("Starts the area selection in any app.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    ShortcutRecorder(settings: settings)
                }

                if let status {
                    Text(status.text)
                        .font(.system(size: 11))
                        .foregroundStyle(status.isError ? Color.red : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !settings.isDefault && !settings.isRecording {
                    Button("Reset to \(Shortcut.screenshotDefault.displayString)") { settings.resetToDefault() }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                }

                Spacer(minLength: 0)
                Divider().opacity(0.6)

                VStack(alignment: .leading, spacing: 6) {
                    Text("⇧⌘3, ⇧⌘4 and ⇧⌘5 belong to macOS. To use one of them here, turn it off under Keyboard Shortcuts › Screenshots first.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Keyboard Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                }
            }
            .padding(16)
        }
        .frame(height: PanelMetrics.shortcutHeight)
    }
}

struct ShortcutRecorder: View {
    @ObservedObject var settings: ShortcutSettings
    @StateObject private var hover = HoverState()

    private var label: String {
        if settings.isRecording {
            let modifiers = Shortcut.symbols(for: settings.liveModifiers)
            return modifiers.isEmpty ? "Type shortcut" : modifiers + "…"
        }
        return settings.screenshot?.displayString ?? "None"
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                settings.isRecording ? settings.cancelRecording() : settings.startRecording()
            } label: {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(settings.isRecording ? Color.accentColor
                                     : (settings.screenshot == nil ? Color.secondary : Color.primary))
                    .frame(minWidth: 96)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(hover.on && !settings.isRecording ? 0.1 : 0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(settings.isRecording ? Color.accentColor : Color.primary.opacity(0.1),
                                          lineWidth: settings.isRecording ? 1.5 : 0.5)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hover.on = $0 }
            .help(settings.isRecording ? "Press the new shortcut" : "Click to record a new shortcut")

            if settings.screenshot != nil && !settings.isRecording {
                Button { settings.clear() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Remove shortcut")
            }
        }
        .animation(.easeOut(duration: 0.12), value: settings.isRecording)
    }
}
