import AVFoundation
import Speech

/// Listens for a short spoken answer, "yes" or "no", after the app asks a question.
/// Recognition runs on the phone when the phone supports it. If permission is missing
/// or recognition fails, nothing happens and the volume button still answers.
@MainActor
final class VoiceListener {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var stopTimer: Task<Void, Never>?
    private var handler: ((SpokenAnswer) -> Void)?
    private var tapInstalled = false
    private var allowed = false

    /// Asks for speech recognition and microphone access. Call once at launch so the
    /// prompts never appear in the middle of a cook.
    func requestPermission() async {
        let speech = await Self.speechAuthorization()
        let microphone = await AVAudioApplication.requestRecordPermission()
        allowed = speech && microphone
    }

    /// Listens for up to `seconds` and calls `onAnswer` once if it hears yes or no.
    func listen(for seconds: Double, onAnswer: @escaping (SpokenAnswer) -> Void) {
        stop()
        guard allowed, let recognizer, recognizer.isAvailable else { return }
        AudioSessionSetup.configure()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.contextualStrings = ["yes", "no", "not now", "start the timer"]

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tap(appendingTo: request))
        tapInstalled = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            stop()
            return
        }

        self.request = request
        handler = onAnswer
        task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler { [weak self] text in
            self?.heard(text)
        })
        stopTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        stopTimer?.cancel()
        stopTimer = nil
        handler = nil
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }

    private func heard(_ text: String) {
        guard let handler, let answer = SpokenAnswer.parse(text) else { return }
        stop()
        handler(answer)
    }

    // These build the callbacks outside the main actor, because speech and audio call
    // them on their own threads.

    nonisolated private static func speechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    nonisolated private static func tap(appendingTo request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }

    nonisolated private static func resultHandler(
        _ onText: @escaping @MainActor (String) -> Void
    ) -> (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { result, _ in
            guard let text = result?.bestTranscription.formattedString else { return }
            Task { @MainActor in onText(text) }
        }
    }
}

/// One audio setup for speaking and listening: play through the speaker (or HDMI), record
/// from the microphone, ignore the silent switch, and mix with any music.
@MainActor
enum AudioSessionSetup {
    private static var configured = false

    static func configure() {
        guard !configured else { return }
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers])
        try? audio.setActive(true)
        configured = true
    }
}
