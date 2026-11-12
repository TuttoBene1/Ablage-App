import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI

@MainActor
final class CaptureController: ObservableObject {
    enum Mode { case photo, video }

    @Published var mode: Mode = .photo

    var onRecordingChange: ((Bool) -> Void)?
    var isRecording: Bool { recorder.isRecording }
    var recordingStartDate: Date? { recorder.startDate }

    private var overlays: [SelectionWindow] = []
    private let recorder = ScreenRecorder()
    private var frameWindow: NSWindow?
    private var isBusy = false
    private var frozenScreens: [CGDirectDisplayID: CGImage] = [:]

    func beginSelection() {
        guard overlays.isEmpty, !recorder.isRecording, !isBusy else { return }
        isBusy = true
        Task { @MainActor in
            // Ask ScreenCaptureKit directly: CGPreflightScreenCaptureAccess() stays stale until the app restarts.
            let content: SCShareableContent
            do {
                content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            } catch {
                isBusy = false
                ScreenPermission.handle(error)
                return
            }
            // Freeze the screens before the overlay covers them, so hover states and tooltips stay in the shot.
            frozenScreens = [:]
            for screen in NSScreen.screens {
                frozenScreens[screen.displayID] = try? await ScreenGrabber.captureDisplay(screen, content: content)
            }
            isBusy = false
            showOverlays()
        }
    }

    private func showOverlays() {
        mode = .photo
        BackgroundCursor.enable()
        let mouseScreen = NSScreen.containingMouse()
        overlays = NSScreen.screens.map { screen in
            SelectionWindow(screen: screen, controller: self, showsToolbar: screen == mouseScreen,
                            frozenImage: frozenScreens[screen.displayID])
        }
        overlays.forEach { $0.present() }
        let keyOverlay = overlays.first { $0.targetScreen == mouseScreen } ?? overlays.first
        keyOverlay?.activate()
        NSCursor.crosshair.set()
    }

    func cancel() {
        dismissOverlays()
        frozenScreens = [:]
    }

    func complete(rect: CGRect, on screen: NSScreen) {
        let mode = self.mode
        let frozen = frozenScreens[screen.displayID]
        frozenScreens = [:]
        dismissOverlays()
        isBusy = true
        Task { @MainActor in
            switch mode {
            case .photo: await takeScreenshot(rect: rect, screen: screen, frozen: frozen)
            case .video: await startRecording(rect: rect, screen: screen)
            }
            isBusy = false
        }
    }

    private func dismissOverlays() {
        let closing = overlays
        overlays.removeAll()
        closing.forEach { $0.orderOut(nil) }
        NSCursor.arrow.set()
        // Release later: this may run inside one of the overlays' own event handlers.
        DispatchQueue.main.async { withExtendedLifetime(closing) {} }
    }

    private func takeScreenshot(rect: CGRect, screen: NSScreen, frozen: CGImage?) async {
        do {
            let image: CGImage
            if let frozen, let cropped = ScreenGrabber.crop(frozen, to: rect, screenSize: screen.frame.size) {
                image = cropped
            } else {
                image = try await ScreenGrabber.capture(rect: rect, screen: screen)
            }
            let rep = NSBitmapImageRep(cgImage: image)
            rep.size = rect.size
            guard let png = rep.representation(using: .png, properties: [:]) else { return }
            PasteboardWriter.writeImage(png: png, origin: PasteboardOrigin.screenshotName)
            Sounds.shutter()
            let pointSize = rect.size
            ScreenshotPreview.shared.show(image: image, pointSize: pointSize, screen: screen) {
                EditorController.open(image: image, pointSize: pointSize, screen: screen)
            }
        } catch {
            presentError(error)
        }
    }

    private func startRecording(rect: CGRect, screen: NSScreen) async {
        do {
            try await recorder.start(rect: rect, screen: screen)
            showRecordingFrame(rect: rect, screen: screen)
            onRecordingChange?(true)
        } catch {
            presentError(error)
        }
    }

    func stopRecording() {
        guard recorder.isRecording else { return }
        hideRecordingFrame()
        Task { @MainActor in
            let url = await recorder.stop()
            onRecordingChange?(false)
            guard let url else {
                Toast.shared.show(symbol: "exclamationmark.triangle", title: "Recording failed", subtitle: nil, on: nil)
                return
            }
            Sounds.endRecording()
            PasteboardWriter.writeFile(url, origin: PasteboardOrigin.recordingName)
            let thumbnail = await Self.thumbnail(for: url)
            Toast.shared.show(image: thumbnail,
                              symbol: "film",
                              title: "Recording saved",
                              subtitle: "Saved to Movies · Click to show",
                              on: nil,
                              duration: 4) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }

    private static func thumbnail(for url: URL) async -> NSImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 200, height: 200)
        guard let result = try? await generator.image(at: .zero) else { return nil }
        let image = result.image
        return NSImage(cgImage: image, size: NSSize(width: image.width / 2, height: image.height / 2))
    }

    private func showRecordingFrame(rect: CGRect, screen: NSScreen) {
        let global = CGRect(x: screen.frame.minX + rect.minX,
                            y: screen.frame.maxY - rect.maxY,
                            width: rect.width, height: rect.height)
        let window = NSWindow(contentRect: global.insetBy(dx: -3, dy: -3),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.contentView = RecordingFrameView()
        window.orderFrontRegardless()
        frameWindow = window
    }

    private func hideRecordingFrame() {
        frameWindow?.orderOut(nil)
        frameWindow = nil
    }

    private func presentError(_ error: Error) {
        NSLog("Ablage capture error: \(error)")
        if ScreenPermission.isPermissionError(error) {
            ScreenPermission.handle(error)
            return
        }
        Toast.shared.show(symbol: "exclamationmark.triangle",
                          title: "Capture failed",
                          subtitle: error.localizedDescription,
                          on: nil)
    }
}

@MainActor
enum ScreenPermission {
    private static let requestedKey = "didRequestScreenCaptureAccess"

    static func isPermissionError(_ error: Error) -> Bool {
        if let scError = error as? SCStreamError, scError.code == .userDeclined { return true }
        let nsError = error as NSError
        return nsError.domain == SCStreamErrorDomain && nsError.code == SCStreamError.Code.userDeclined.rawValue
    }

    static func handle(_ error: Error) {
        guard isPermissionError(error) else {
            NSLog("Ablage capture error: \(error)")
            Toast.shared.show(symbol: "exclamationmark.triangle", title: "Capture failed",
                              subtitle: error.localizedDescription, on: nil)
            return
        }
        if !UserDefaults.standard.bool(forKey: requestedKey) {
            UserDefaults.standard.set(true, forKey: requestedKey)
            _ = CGRequestScreenCaptureAccess()
            return
        }
        showSettingsAlert()
    }

    static func showSettingsAlert() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Allow Screen Recording"
        alert.informativeText = "macOS denied Ablage access to the screen. Turn on “Ablage” in System Settings › Privacy & Security › Screen & System Audio Recording. If it is already on, turn it off and on again."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum CaptureError: LocalizedError {
    case displayNotFound
    var errorDescription: String? { "The display could not be found." }
}

@MainActor
enum ScreenGrabber {
    static func filter(for screen: NSScreen) async throws -> SCContentFilter {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return try filter(for: screen, in: content)
    }

    static func filter(for screen: NSScreen, in content: SCShareableContent) throws -> SCContentFilter {
        let displayID = screen.displayID
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let own = content.applications.filter { $0.processID == pid }
        return SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
    }

    static func capture(rect: CGRect, screen: NSScreen) async throws -> CGImage {
        let filter = try await filter(for: screen)
        let scale = screen.backingScaleFactor
        let config = SCStreamConfiguration()
        config.sourceRect = rect
        config.width = max(1, Int((rect.width * scale).rounded()))
        config.height = max(1, Int((rect.height * scale).rounded()))
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    static func captureDisplay(_ screen: NSScreen, content: SCShareableContent) async throws -> CGImage {
        let filter = try filter(for: screen, in: content)
        let scale = screen.backingScaleFactor
        let config = SCStreamConfiguration()
        config.width = max(1, Int((screen.frame.width * scale).rounded()))
        config.height = max(1, Int((screen.frame.height * scale).rounded()))
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// `rect` is in points with a top-left origin, like the selection.
    static func crop(_ image: CGImage, to rect: CGRect, screenSize: CGSize) -> CGImage? {
        guard screenSize.width > 0 else { return nil }
        let scale = CGFloat(image.width) / screenSize.width
        let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale,
                            width: rect.width * scale, height: rect.height * scale).integral
        return image.cropping(to: pixels)
    }
}

// Private CoreGraphics flag that lets the crosshair show while another app stays frontmost.
@MainActor
enum BackgroundCursor {
    private typealias ConnectionFn = @convention(c) () -> Int32
    private typealias SetPropertyFn = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
    private static var enabled = false

    static func enable() {
        guard !enabled else { return }
        enabled = true
        let handle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let connection = dlsym(handle, "_CGSDefaultConnection") ?? dlsym(handle, "CGSMainConnectionID"),
              let setProperty = dlsym(handle, "CGSSetConnectionProperty") else { return }
        let cid = unsafeBitCast(connection, to: ConnectionFn.self)()
        _ = unsafeBitCast(setProperty, to: SetPropertyFn.self)(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }
}

final class RecordingFrameView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1.5, dy: 1.5)
        let outer = NSBezierPath(rect: rect.insetBy(dx: -0.75, dy: -0.75))
        outer.lineWidth = 0.75
        NSColor.black.withAlphaComponent(0.35).setStroke()
        outer.stroke()
        let line = NSBezierPath(rect: rect)
        line.lineWidth = 1.5
        line.setLineDash([6, 4], count: 2, phase: 0)
        NSColor.white.withAlphaComponent(0.9).setStroke()
        line.stroke()
    }
}
