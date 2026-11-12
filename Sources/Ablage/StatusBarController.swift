import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSWindowDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let panel = FloatingPanel()
    let model: PanelModel
    private let capture: CaptureController
    private let quickPaste: QuickPasteController
    private var outsideClickMonitor: Any?
    private var recordingTimer: Timer?
    private var contentSize = CGSize(width: PanelMetrics.width, height: 162)
    private var isClosing = false
    private var routeObserver: AnyCancellable?

    init(clipboard: ClipboardStore, capture: CaptureController, shortcuts: ShortcutSettings) {
        self.capture = capture
        self.quickPaste = QuickPasteController(store: clipboard)
        self.model = PanelModel(store: clipboard, shortcuts: shortcuts)
        super.init()
        configureStatusItem()
        configurePanel()

        model.onScreenshot = { [weak self] in self?.startScreenshot() }
        model.onClose = { [weak self] in self?.closePanel() }
        model.onQuit = { NSApp.terminate(nil) }
        capture.onRecordingChange = { [weak self] recording in self?.updateRecordingState(recording) }
        HotKeyCenter.shared.onPress = { [weak self] action in self?.handleHotKey(action) }
    }

    private func handleHotKey(_ action: ShortcutAction) {
        switch action {
        case .screenshot:
            quickPaste.close()
            if capture.isRecording {
                capture.stopRecording()
            } else {
                startScreenshot()
            }
        case .clipboard:
            closePanel(animated: false)
            quickPaste.toggle()
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = Self.idleIcon
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityTitle("Ablage")
    }

    private static var idleIcon: NSImage {
        symbol("rectangle.dashed.and.paperclip", fallback: "paperclip")
    }

    private static var stopIcon: NSImage {
        symbol("stop.circle", fallback: "stop.fill")
    }

    private static func symbol(_ name: String, fallback: String) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let base = NSImage(systemSymbolName: name, accessibilityDescription: "Ablage")
            ?? NSImage(systemSymbolName: fallback, accessibilityDescription: "Ablage")
            ?? NSImage()
        let image = base.withSymbolConfiguration(config) ?? base
        image.isTemplate = true
        return image
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if capture.isRecording {
            capture.stopRecording()
            return
        }
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            closePanel(animated: false)
            showContextMenu()
            return
        }
        if panel.isVisible && !isClosing {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let screenshot = NSMenuItem(title: "Take Screenshot", action: #selector(menuScreenshot), keyEquivalent: "")
        screenshot.target = self
        menu.addItem(screenshot)
        let clipboard = NSMenuItem(title: "Clipboard", action: #selector(menuClipboard), keyEquivalent: "")
        clipboard.target = self
        menu.addItem(clipboard)
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = model.launchAtLogin ? .on : .off
        menu.addItem(login)
        let shortcut = NSMenuItem(title: "Keyboard Shortcuts…", action: #selector(menuShortcut), keyEquivalent: "")
        shortcut.target = self
        menu.addItem(shortcut)
        menu.addItem(.separator())
        let about = NSMenuItem(title: "About Ablage", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let website = NSMenuItem(title: "Webforging – App Development", action: #selector(openWebsite), keyEquivalent: "")
        website.target = self
        menu.addItem(website)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Ablage", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuScreenshot() { startScreenshot() }

    @objc private func menuClipboard() {
        showPanel()
        model.showClipboard()
    }

    @objc private func menuShortcut() {
        showPanel()
        model.showShortcut()
    }

    @objc private func toggleLogin() { model.launchAtLogin.toggle() }

    @objc private func showAbout() { AppInfo.showAbout() }

    @objc private func openWebsite() { NSWorkspace.shared.open(AppInfo.website) }

    private func configurePanel() {
        let background = Chrome.background(radius: Chrome.panelRadius)
        panel.contentView = background

        let root = PanelRootView(model: model, store: model.store)
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = background.bounds
        background.addSubview(hosting)

        panel.delegate = self
        panel.keyHandler = { [weak self] event in self?.model.handleKey(event) ?? false }
        panel.onCancel = { [weak self] in self?.closePanel() }

        contentSize = size(for: model.route)
        panel.setFrame(frameForPanel(size: contentSize), display: false)
        routeObserver = model.$route
            .removeDuplicates()
            .sink { [weak self] route in
                guard let self else { return }
                self.contentSizeChanged(self.size(for: route))
            }
    }

    private lazy var homeHeight: CGFloat = {
        let probe = NSHostingView(rootView: HomeView(model: model, store: model.store)
            .frame(width: PanelMetrics.width)
            .fixedSize(horizontal: false, vertical: true))
        let height = probe.fittingSize.height
        return height > 40 ? ceil(height) : 162
    }()

    private func size(for route: PanelModel.Route) -> CGSize {
        switch route {
        case .home: return CGSize(width: PanelMetrics.width, height: homeHeight)
        case .clipboard: return CGSize(width: PanelMetrics.width, height: PanelMetrics.clipboardHeight)
        case .shortcut: return CGSize(width: PanelMetrics.width, height: PanelMetrics.shortcutHeight)
        }
    }

    private func frameForPanel(size: CGSize) -> NSRect {
        guard let button = statusItem.button, let window = button.window else {
            return NSRect(origin: .zero, size: size)
        }
        let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        var x = buttonRect.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let top = min(buttonRect.minY, visible.maxY) - 6
        return NSRect(x: round(x), y: round(top - size.height), width: size.width, height: size.height)
    }

    private func contentSizeChanged(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let rounded = CGSize(width: ceil(size.width), height: ceil(size.height))
        guard rounded != contentSize else { return }
        contentSize = rounded
        let frame = frameForPanel(size: rounded)
        if panel.isVisible && !isClosing {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated { self?.panel.invalidateShadow() }
            })
        } else {
            panel.setFrame(frame, display: false)
            panel.invalidateShadow()
        }
    }

    func showPanel() {
        isClosing = false
        panel.setFrame(frameForPanel(size: contentSize), display: true)
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }
        statusItem.button?.highlight(true)
        startOutsideClickMonitor()
    }

    func closePanel(animated: Bool = true) {
        guard panel.isVisible, !isClosing else { return }
        isClosing = true
        stopOutsideClickMonitor()
        statusItem.button?.highlight(false)

        let finish: () -> Void = { [weak self] in
            guard let self, self.isClosing else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
            self.isClosing = false
            self.model.reset()
        }
        guard animated else { finish(); return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { finish() }
        })
    }

    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePanel() }
        }
    }

    private func stopOutsideClickMonitor() {
        if let monitor = outsideClickMonitor { NSEvent.removeMonitor(monitor) }
        outsideClickMonitor = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        closePanel()
    }

    private func startScreenshot() {
        closePanel(animated: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.capture.beginSelection()
        }
    }

    private func updateRecordingState(_ recording: Bool) {
        guard let button = statusItem.button else { return }
        recordingTimer?.invalidate()
        recordingTimer = nil
        if recording {
            closePanel(animated: false)
            button.image = Self.stopIcon
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            updateElapsedTime()
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateElapsedTime() }
            }
            RunLoop.main.add(timer, forMode: .common)
            recordingTimer = timer
            button.toolTip = "Stop Recording"
        } else {
            button.image = Self.idleIcon
            button.title = ""
            button.toolTip = nil
        }
    }

    private func updateElapsedTime() {
        guard let start = capture.recordingStartDate else { return }
        let seconds = max(0, Int(Date().timeIntervalSince(start)))
        statusItem.button?.title = String(format: " %d:%02d", seconds / 60, seconds % 60)
    }
}
