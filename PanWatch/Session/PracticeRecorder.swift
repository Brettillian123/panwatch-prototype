import CoreMedia
import Foundation

/// Writes a practice recording (see `PracticeRecording`) while the debug panel's switch is
/// on: every analyzed frame's hands and a small picture of the pan box, the cook's "that
/// was it" markers, and the app's own decisions. No video and no audio.
///
/// Frames and decisions arrive on the camera queue; the switch, markers and step changes
/// come from the main thread.
final class PracticeRecorder: @unchecked Sendable {
    struct Status: Sendable {
        var isRecording = false
        var seconds = 0.0
        var bytes = 0
        var markers = 0
        /// The latest recording, kept after it stops so it can be shared.
        var file: URL?
    }

    private let lock = NSLock()
    private var handle: FileHandle?
    private var pending = Data()
    private var status = Status()
    private var firstTime: Double?
    private var stepIndex = 0
    private var watch: PracticeRecording.StepWatch?

    /// Writes reach the file in pieces about this big, a few times a minute.
    private static let flushSize = 1 << 20

    var current: Status { lock.withLock { status } }

    /// Starts a new file in the app's Documents/Practice folder.
    func start(notes: String, settings: DetectorSettings) throws {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Practice", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let url = folder.appendingPathComponent("practice-\(formatter.string(from: Date())).pwrec")
        var data = PracticeRecording.header(notes: notes)
        data.append(PracticeRecording.encode(PracticeRecording.Tuning(time: Self.now, settings: settings)))
        try data.write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        lock.withLock {
            self.handle = handle
            pending = Data()
            firstTime = nil
            status = Status(isRecording: true, bytes: data.count, file: url)
        }
    }

    func stop() {
        lock.withLock {
            flush()
            try? handle?.close()
            handle = nil
            status.isRecording = false
        }
    }

    /// The step the cook is on, written into every frame after this.
    func setStep(_ index: Int, watch: AdditionWatch?) {
        lock.withLock {
            stepIndex = index
            self.watch = watch.map(PracticeRecording.StepWatch.init)
        }
    }

    /// The cook changed the tuning.
    func setTuning(_ settings: DetectorSettings) {
        append(PracticeRecording.encode(PracticeRecording.Tuning(time: Self.now, settings: settings)))
    }

    /// The cook said "that was it". False when nothing is being recorded.
    func mark() -> Bool {
        lock.withLock {
            guard handle != nil else { return false }
            write(PracticeRecording.encodeMarker(at: Self.now))
            status.markers += 1
            return true
        }
    }

    /// One analyzed frame. `patch` is the full-size pan box; it's shrunk here.
    func record(time: Double, frameWidth: Int, frameHeight: Int, armed: Bool, hands: [HandReading], region: NormRect?, patch: PanPatch?) {
        lock.withLock {
            guard handle != nil else { return }
            let frame = PracticeRecording.Frame(
                time: time, frameWidth: frameWidth, frameHeight: frameHeight, stepIndex: stepIndex,
                watch: watch, armed: armed, hands: hands, region: region, patch: patch
            )
            write(PracticeRecording.encode(frame))
            firstTime = firstTime ?? time
            status.seconds = time - (firstTime ?? time)
        }
    }

    func noteDecision(_ decision: DetectorDecision) {
        lock.withLock {
            guard handle != nil else { return }
            write(PracticeRecording.encode(PracticeRecording.Verdict(time: decision.time, outcome: decision.outcome, stepIndex: stepIndex)))
        }
    }

    /// Capture times are on the host clock, so markers use it too.
    private static var now: Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

    private func append(_ data: Data) {
        lock.withLock {
            guard handle != nil else { return }
            write(data)
        }
    }

    // Called with `lock` held.
    private func write(_ data: Data) {
        pending.append(data)
        status.bytes += data.count
        if pending.count >= Self.flushSize { flush() }
    }

    // Called with `lock` held.
    private func flush() {
        guard let handle, !pending.isEmpty else { return }
        do {
            try handle.write(contentsOf: pending)
        } catch {
            // Out of space or the file went away: stop rather than fail every frame.
            try? handle.close()
            self.handle = nil
            status.isRecording = false
        }
        pending = Data()
    }
}
