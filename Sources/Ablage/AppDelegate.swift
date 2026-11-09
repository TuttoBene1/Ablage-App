import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let clipboard = ClipboardStore()
    private var capture: CaptureController!
    private var statusBar: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        clipboard.start()
        capture = CaptureController()
        statusBar = StatusBarController(clipboard: clipboard, capture: capture)
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboard.saveNow()
    }
}
