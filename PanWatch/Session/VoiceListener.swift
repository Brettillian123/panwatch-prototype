import AVFoundation
import Speech

/// Listens for spoken commands the whole time the app is open: "next", "back", "repeat",
/// "start the timer", "yes", "no". Recognition runs on the phone when the phone supports
/// it. Each utterance is judged once the cook pauses, so only short phrases count, and
/// listening pauses while the app itself is talking so it never hears its own voice.
/// If permission is missing or recognition fails, nothing happens and the volume buttons
/// and the screen still work.
@MainActor
final class VoiceListener {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private let feed = AudioFeed()
    private var task: SFSpeechRecognitionTask?
    private var pauseTimer: Task<Void, Never>?
    private var restartTimer: Task<Void, Never>?
    private var configurationObserver: (any NSObjectProtocol)?
    private var handler: ((VoiceCommand, String) -> Void)?
    private var transcript = ""
    /// Bumped for every new recognition request, so late results from an old one are ignored.
    private var generation = 0
    private var failures = 0
    private var tapInstalled = false
    private var allowed = false
    /// Listening was asked for and not stopped.
    private var wanted = false
    /// The app is talking.
    private var held = false

    /// How long a pause ends an utterance.
    private static let pauseLength = 0.8
    /// Recognition requests are limited to about a minute, so each is replaced sooner.
    private static let requestLifetime = 50.0

    /// Asks for speech recognition and microphone access. Call once at launch so the
    /// prompts never appear in the middle of a cook.
    func requestPermission() async -> Bool {
        let speech = await Self.speechAuthorization()
        let microphone = await AVAudioApplication.requestRecordPermission()
        allowed = speech && microphone
        return allowed
    }

    /// Starts listening for commands until `stop()`.
    func start(onCommand: @escaping (VoiceCommand, String) -> Void) {
        handler = onCommand
        guard !wanted else { return }
        wanted = true
        guard startEngine() else {
            wanted = false
            return
        }
        beginRequest()
    }

    func stop() {
        wanted = false
        handler = nil
        endRequest()
        stopEngine()
    }

    /// Pauses while the app talks, so it doesn't hear itself.
    func hold() {
        held = true
        endRequest()
    }

    /// Picks up again once the app has finished talking.
    func resume() {
        held = false
        guard wanted else { return }
        let current = generation
        // A short gap, so the end of the app's own sentence isn't heard.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.3))
            guard let self, self.generation == current, self.wanted, !self.held, self.task == nil else { return }
            self.beginRequest()
        }
    }

    // MARK: Recognition

    private func beginRequest() {
        endRequest()
        guard wanted, !held, allowed, let recognizer, recognizer.isAvailable else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.contextualStrings = ["next step", "go back", "repeat", "start the timer", "yes", "no", "not now", "time left", "start watching"]
        generation += 1
        let current = generation
        transcript = ""
        feed.set(request)
        task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler { [weak self] text, isFinal, failed in
            self?.received(text, isFinal: isFinal, failed: failed, generation: current)
        })
        restartTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.requestLifetime))
            guard let self, !Task.isCancelled, self.generation == current else { return }
            self.utteranceEnded()
        }
    }

    private func endRequest() {
        generation += 1
        pauseTimer?.cancel()
        pauseTimer = nil
        restartTimer?.cancel()
        restartTimer = nil
        feed.set(nil)
        task?.cancel()
        task = nil
        transcript = ""
    }

    private func received(_ text: String?, isFinal: Bool, failed: Bool, generation current: Int) {
        guard current == generation else { return }
        if let text, !text.isEmpty {
            failures = 0
            transcript = text
            if isFinal {
                utteranceEnded()
                return
            }
            // Judge the utterance once the cook stops talking.
            pauseTimer?.cancel()
            pauseTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.pauseLength))
                guard let self, !Task.isCancelled, self.generation == current else { return }
                self.utteranceEnded()
            }
        } else if failed || isFinal {
            // Recognition stopped, for example after a long silence. Start again, backing
            // off if it keeps failing.
            failures += 1
            endRequest()
            let delay = min(5.0, 0.5 * Double(failures))
            let next = generation
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard let self, self.generation == next, self.wanted, !self.held else { return }
                self.beginRequest()
            }
        }
    }

    /// Acts on what was said, then starts a fresh request for the next utterance.
    private func utteranceEnded() {
        let text = transcript
        endRequest()
        if let command = VoiceCommand.parse(text) {
            handler?(command, text)
        }
        // The command may have made the app talk, which holds listening until it's done.
        if wanted, !held { beginRequest() }
    }

    // MARK: Audio

    private func startEngine() -> Bool {
        guard allowed, recognizer != nil else { return false }
        AudioSessionSetup.configure()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }
        if !tapInstalled {
            input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tap(feeding: feed))
            tapInstalled = true
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            stopEngine()
            return false
        }
        if configurationObserver == nil {
            // Plugging in a display or headphones stops the engine; start it again.
            configurationObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.restartEngine() }
            }
        }
        return true
    }

    private func stopEngine() {
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }

    private func restartEngine() {
        guard wanted else { return }
        endRequest()
        stopEngine()
        guard startEngine() else { return }
        if !held { beginRequest() }
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

    nonisolated private static func tap(feeding feed: AudioFeed) -> AVAudioNodeTapBlock {
        { buffer, _ in feed.append(buffer) }
    }

    nonisolated private static func resultHandler(
        _ onResult: @escaping @MainActor (String?, Bool, Bool) -> Void
    ) -> (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in onResult(text, isFinal, failed) }
        }
    }
}

/// Hands microphone audio to whichever recognition request is current. The audio thread
/// appends while the main thread swaps requests, so a lock guards it.
private final class AudioFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ newRequest: SFSpeechAudioBufferRecognitionRequest?) {
        let previous: SFSpeechAudioBufferRecognitionRequest? = lock.withLock {
            let current = request
            request = newRequest
            return current
        }
        previous?.endAudio()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { request }?.append(buffer)
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
