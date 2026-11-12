import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let clipboard = ClipboardStore()
    private var capture: CaptureController!
    private var statusBar: StatusBarController!
    private let shortcuts = ShortcutSettings()

    func applicationDidFinishLaunching(_ notification: Notification) {
        clipboard.start()
        capture = CaptureController()
        statusBar = StatusBarController(clipboard: clipboard, capture: capture, shortcuts: shortcuts)
        shortcuts.activate()
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboard.saveNow()
    }
}
