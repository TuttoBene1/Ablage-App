import AppKit
import AVFoundation
import ScreenCaptureKit

/// Records a region of one display straight into a .mov file in ~/Movies.
@MainActor
final class ScreenRecorder {
    private(set) var isRecording = false
    private(set) var startDate: Date?

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var outputURL: URL?
    private let sink = FrameSink()
    private var finishWatcher: RecordingFinishWatcher?

    func start(rect: CGRect, screen: NSScreen) async throws {
        guard !isRecording else { return }
        let filter = try await ScreenGrabber.filter(for: screen)
        let scale = screen.backingScaleFactor

        let config = SCStreamConfiguration()
        config.sourceRect = rect
        config.width = Self.even(rect.width * scale)
        config.height = Self.even(rect.height * scale)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = true
        config.queueDepth = 6
        config.capturesAudio = false

        let url = Self.makeOutputURL()
        let outputConfig = SCRecordingOutputConfiguration()
        outputConfig.outputURL = url
        outputConfig.outputFileType = .mov
        outputConfig.videoCodecType = .h264

        let watcher = RecordingFinishWatcher()
        let output = SCRecordingOutput(configuration: outputConfig, delegate: watcher)
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
        try stream.addRecordingOutput(output)
        try await stream.startCapture()

        self.stream = stream
        self.recordingOutput = output
        self.finishWatcher = watcher
        self.outputURL = url
        isRecording = true
        startDate = Date()
    }

    /// Stops the recording and returns the finished file, or nil if it failed.
    func stop() async -> URL? {
        guard isRecording, let stream else { return nil }
        isRecording = false
        try? await stream.stopCapture()
        await finishWatcher?.waitUntilFinished(timeout: 4)

        let url = outputURL
        self.stream = nil
        recordingOutput = nil
        finishWatcher = nil
        outputURL = nil
        startDate = nil

        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private static func even(_ value: CGFloat) -> Int {
        max(2, Int(value.rounded()) & ~1)
    }

    private static func makeOutputURL() -> URL {
        let folder = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "yyyy-MM-dd 'um' HH.mm.ss"
        let base = "Bildschirmaufnahme \(formatter.string(from: Date()))"
        var url = folder.appendingPathComponent(base + ".mov")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(counter).mov")
            counter += 1
        }
        return url
    }
}

/// Receives (and drops) the raw frames; the recording output writes the file.
private final class FrameSink: NSObject, SCStreamOutput {
    let queue = DispatchQueue(label: "ablage.recorder.frames", qos: .userInitiated)
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {}
}

private final class RecordingFinishWatcher: NSObject, SCRecordingOutputDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { markFinished() }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        NSLog("Ablage recording failed: \(error)")
        markFinished()
    }

    private func markFinished() {
        lock.lock()
        finished = true
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        pending.forEach { $0.resume() }
    }

    func waitUntilFinished(timeout: TimeInterval) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if finished {
                lock.unlock()
                continuation.resume()
                return
            }
            waiters.append(continuation)
            lock.unlock()
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.markFinished()
            }
        }
    }
}
