import AVFoundation

/// What the screen needs to know about the latest analyzed frame.
struct AnalyzerSnapshot: Sendable {
    var frameWidth = 0
    var frameHeight = 0
    /// Every hand Vision reported, counted or not. Its count is "hands seen".
    var hands: [[NormPoint]] = []
    /// Hands the filter believes are real.
    var handsCounted = 0
    /// Hands seen but ignored because they haven't moved.
    var handsIgnoredAsStill = 0
    var handInZone = false
    var phase: AdditionDetector.Phase = .disarmed
    var dwell = 0.0
    var motion = 0.0
    var liveChange = 0.0
    var handOpenness: Double?
    var handOpened = 0.0
    /// Warm-up gave up and learned the pan with a hand in view.
    var learnedWithHand = false
    var analysisFPS = 0.0
    /// Why nothing was offered lately: a hand that didn't count, a visit too short, and so on.
    var noOffer: NoOffer?
}

/// Receives every camera frame on the capture queue. It shows each one, and on every
/// other frame runs hand tracking and the addition detector.
final class FrameAnalyzer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    // Set from the main thread, read on the frame queue. Guarded by `lock`.
    private let lock = NSLock()
    private var region: NormRect?
    private var armed = false
    private var settings = DetectorSettings()
    private var renderer: AVSampleBufferVideoRenderer?
    private var snapshotHandler: (@Sendable (AnalyzerSnapshot) -> Void)?
    private var decisionHandler: (@Sendable (DetectorDecision) -> Void)?

    /// Writes practice recordings while the debug panel's switch is on. Thread-safe.
    let recorder = PracticeRecorder()

    // Only touched on the frame queue.
    private var watcher = PanWatcher()
    private let handDetector = HandPoseDetector()
    private var frameCount = 0
    private var lastAnalysisTime: Double?
    private var analysisFPS = 0.0

    /// Called about 15 times a second with the latest state.
    var onSnapshot: (@Sendable (AnalyzerSnapshot) -> Void)? {
        get { lock.withLock { snapshotHandler } }
        set { lock.withLock { snapshotHandler = newValue } }
    }

    /// Called when a visit to the pan has been judged.
    var onDecision: (@Sendable (DetectorDecision) -> Void)? {
        get { lock.withLock { decisionHandler } }
        set { lock.withLock { decisionHandler = newValue } }
    }

    func update(settings: DetectorSettings) { lock.withLock { self.settings = settings } }
    func setRegion(_ region: NormRect?) { lock.withLock { self.region = region } }
    /// Only armed during recipe steps that add something, and only once the pan is marked.
    func setArmed(_ armed: Bool) { lock.withLock { self.armed = armed } }
    func attach(renderer: AVSampleBufferVideoRenderer) { lock.withLock { self.renderer = renderer } }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let (region, armed, settings, renderer, onSnapshot, onDecision) = lock.withLock {
            (self.region, self.armed, self.settings, self.renderer, snapshotHandler, decisionHandler)
        }
        if let renderer { show(sampleBuffer, on: renderer) }

        // 15 analyses a second is plenty to catch a hand, and half the heat of 30 over a long cook.
        frameCount &+= 1
        guard frameCount % 2 == 0, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        trackRate(at: time)

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let readings = handDetector.readings(in: pixelBuffer)
        let patch = region.flatMap { PanPatch.sample(from: pixelBuffer, rect: $0) }
        // Which hands count, whether one is over the pan, and the verdict: shared with the
        // practice replay, so a recording is judged the way this frame is.
        watcher.settings = settings
        let result = watcher.process(
            time: time, hands: readings, aspect: height > 0 ? Double(width) / Double(height) : 1,
            region: region, patch: patch, armed: armed
        )
        recorder.record(time: time, frameWidth: width, frameHeight: height, armed: armed, hands: readings, region: region, patch: patch)
        if let decision = result.decision {
            recorder.noteDecision(decision)
            onDecision?(decision)
        }
        let detector = watcher.detector
        var snapshot = AnalyzerSnapshot(
            frameWidth: width,
            frameHeight: height,
            hands: result.seen.map(\.joints),
            handsCounted: result.handsCounted,
            handsIgnoredAsStill: result.handsIgnoredAsStill,
            handInZone: result.handInZone,
            handOpenness: result.handOpenness,
            analysisFPS: analysisFPS,
            noOffer: watcher.noOffer
        )
        snapshot.phase = detector.phase
        snapshot.dwell = detector.dwell
        snapshot.motion = detector.motion
        snapshot.liveChange = detector.liveChange
        snapshot.handOpened = detector.handOpened
        snapshot.learnedWithHand = detector.learnedWithHand
        onSnapshot?(snapshot)
    }

    private func show(_ sampleBuffer: CMSampleBuffer, on renderer: AVSampleBufferVideoRenderer) {
        if renderer.status == .failed { renderer.flush() }
        // Never enqueue into a full renderer; drop the frame instead of piling them up.
        guard renderer.isReadyForMoreMediaData else { return }
        // Camera frames carry capture timestamps. Tell the layer to draw each frame as it
        // arrives instead of scheduling it against a clock it doesn't have.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let first = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                first,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }
        renderer.enqueue(sampleBuffer)
    }

    private func trackRate(at time: Double) {
        if let last = lastAnalysisTime, time > last {
            let instant = 1 / (time - last)
            analysisFPS = analysisFPS == 0 ? instant : analysisFPS * 0.9 + instant * 0.1
        }
        lastAnalysisTime = time
    }
}
