import AppKit
import SwiftUI

struct ShortcutView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var settings: ShortcutSettings

    private func status(for action: ShortcutAction) -> (text: String, isError: Bool)? {
        if settings.recording == action { return ("Press the new shortcut. esc cancels, ⌫ removes it.", false) }
        if let message = settings.message, message.action == action { return (message.text, true) }
        if settings.unavailable.contains(action), let shortcut = settings.shortcut(for: action) {
            return ("\(shortcut.displayString) could not be registered – choose a different one.", true)
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Keyboard Shortcuts")
                    .font(.system(size: 13, weight: .semibold))
                HStack {
                    IconButton(symbol: "chevron.left", help: "Back") { model.showHome() }
                    Spacer()
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 42)

            Divider().opacity(0.6)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(ShortcutAction.allCases) { action in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.title)
                                    .font(.system(size: 13, weight: .medium))
                                Text(action.subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            ShortcutRecorder(settings: settings, action: action)
                        }
                        if let status = status(for: action) {
                            Text(status.text)
                                .font(.system(size: 11))
                                .foregroundStyle(status.isError ? Color.red : Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if settings.hasChanges && !settings.isRecording {
                    Button("Reset to Defaults") { settings.resetToDefaults() }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                }

                Spacer(minLength: 0)
                Divider().opacity(0.6)

                VStack(alignment: .leading, spacing: 6) {
                    if !AccessibilityAccess.isTrusted {
                        Text("To paste into the text field directly, allow Ablage under Privacy & Security › Accessibility.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Allow Accessibility…") { AccessibilityAccess.openSettings() }
                            .buttonStyle(.link)
                            .font(.system(size: 11))
                    } else {
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
            }
            .padding(16)
        }
        .frame(height: PanelMetrics.shortcutHeight)
    }
}

struct ShortcutRecorder: View {
    @ObservedObject var settings: ShortcutSettings
    let action: ShortcutAction
    @StateObject private var hover = HoverState()

    private var isRecording: Bool { settings.recording == action }

    private var label: String {
        if isRecording {
            let modifiers = Shortcut.symbols(for: settings.liveModifiers)
            return modifiers.isEmpty ? "Type shortcut" : modifiers + "…"
        }
        return settings.shortcut(for: action)?.displayString ?? "None"
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                isRecording ? settings.cancelRecording() : settings.startRecording(action)
            } label: {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isRecording ? Color.accentColor
                                     : (settings.shortcut(for: action) == nil ? Color.secondary : Color.primary))
                    .frame(minWidth: 96)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(hover.on && !isRecording ? 0.1 : 0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isRecording ? Color.accentColor : Color.primary.opacity(0.1),
                                          lineWidth: isRecording ? 1.5 : 0.5)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hover.on = $0 }
            .help(isRecording ? "Press the new shortcut" : "Click to record a new shortcut")

            Button { settings.clear(action) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Remove shortcut")
            .opacity(settings.shortcut(for: action) != nil && !isRecording ? 1 : 0)
            .allowsHitTesting(settings.shortcut(for: action) != nil && !isRecording)
        }
        .animation(.easeOut(duration: 0.12), value: isRecording)
    }
}
