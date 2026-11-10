import AVFoundation
import Speech

/// Listens for spoken commands the whole time the app is open: "next", "back", "repeat",
/// "start the timer", "yes", "no". Recognition runs on the phone when the phone supports
/// it. Each utterance is judged once the cook pauses, so only short phrases count.
/// Listening goes on while the app talks (voice processing keeps the app's voice out of
/// the microphone) and the cook speaking cuts the app short; without voice processing,
/// listening pauses while the app talks so it never hears its own voice.
/// If permission is missing or recognition fails, nothing happens and the volume buttons
/// and the screen still work. A watchdog starts listening again whatever stopped it.
@MainActor
final class VoiceListener {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    /// The engine shared with the speaker, so its voice processing cancels the app's own voice.
    private let audio: AudioIO
    private let feed = AudioFeed()
    /// Watches the microphone level for the cook starting to talk over the app.
    private let levelGate = LevelGate()
    private var task: SFSpeechRecognitionTask?
    private var pauseTimer: Task<Void, Never>?
    private var restartTimer: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var configurationObserver: (any NSObjectProtocol)?
    private var sessionObservers: [any NSObjectProtocol] = []
    private var handler: ((VoiceCommand, String) -> Void)?
    private var transcript = ""
    /// Bumped for every new recognition request, so late results from an old one are ignored.
    private var generation = 0
    private var failures = 0
    private var allowed = false
    /// Listening was asked for and not stopped.
    private var wanted = false
    /// Listening is paused while the app talks (only without voice processing).
    private var held = false
    var isHeld: Bool { held }
    /// What the app was saying when this utterance began, so its own words are left out.
    private var spokenDuring: String?
    /// When the app last finished saying something, for the follow-up window.
    private var repliedAt: Date?
    private var heldSince: Date?
    /// When a recognition request was last running, for the watchdog.
    private var lastActive = Date.now
    private var requestStarted = Date.now
    /// Recognition runs on the phone when it can. Off after on-phone requests keep failing
    /// at once, which happens while the phone's speech model is missing or downloading.
    private var preferOnDevice = true
    private var requestOnDevice = false

    /// Whether the app is still talking, so a "finished talking" that never came can't
    /// hold listening for good.
    var isAppSpeaking: (() -> Bool)?
    /// What the app is saying right now, for the self-echo guard.
    var spokenText: (() -> String?)?
    /// The cook started talking over the app: stop the app's voice at once.
    var onBargeIn: (() -> Void)?
    /// The screen showing, since the recipe menu also takes one word of a dish's name.
    var screen: (() -> AppScreen)?
    /// Called whenever `report` changes.
    var onReport: ((VoiceReport) -> Void)?
    private(set) var report = VoiceReport() {
        didSet { if report != oldValue { onReport?(report) } }
    }
    /// What the app is showing, for the on-device model that reads what the keywords miss.
    /// Without it, or without the model on this phone, the keywords are all there is.
    var intentContext: (() -> IntentContext?)?
    private let intentReader = IntentReader()
    /// The recipe as the assistant sees it. With the on-device model, what the keywords
    /// miss goes to the assistant instead of `intentReader`.
    var assistantContext: (() -> AssistantContext?)?
    /// The assistant's reply, or the food-safety table's, for words the keywords missed;
    /// only while it still fits: no newer utterance, the same recipe, step and offer.
    var onAssistant: ((CookAssistant.Reply, String) -> Void)?
    private let assistant = CookAssistant()
    /// The last few assistant turns, newest first, for the debug panel.
    private static let turnsShown = 3
    /// Bumped for every utterance, so a model answer that comes back after the cook said
    /// something else is dropped.
    private var utterances = 0

    /// The app finished a line: words the keywords miss still reach the model for a few
    /// seconds, so a follow-up needs no command words.
    func appStoppedSpeaking() {
        repliedAt = .now
    }
    /// Recognition requests are limited to about a minute, so each is replaced sooner.
    private static let requestLifetime = 50.0
    /// With no recognition request for this long, the watchdog starts one.
    private static let watchdogDelay = 3.0

    init(audio: AudioIO) {
        self.audio = audio
        levelGate.onSpeech = { [weak self] in
            Task { @MainActor in self?.heardSpeechLevel() }
        }
    }

    /// Asks for speech recognition and microphone access. Call once at launch so the
    /// prompts never appear in the middle of a cook.
    func requestPermission() async -> Bool {
        let speech = await Self.speechAuthorization()
        let microphone = await AVAudioApplication.requestRecordPermission()
        allowed = speech && microphone
        updateState()
        return allowed
    }

    /// Starts listening for commands until `stop()`.
    func start(onCommand: @escaping (VoiceCommand, String) -> Void) {
        handler = onCommand
        guard !wanted else { return }
        wanted = true
        if assistant.isAvailable { assistant.prepare() } else { intentReader.prepare() }
        if !intentReader.isAvailable { report.model = "Off: keywords only" }
        observeAudioSession()
        startWatchdog()
        // If the microphone can't start yet, the watchdog tries again.
        if startEngine() { beginRequest() }
        updateState()
    }

    func stop() {
        wanted = false
        handler = nil
        utterances += 1
        intentReader.release()
        assistant.release()
        watchdog?.cancel()
        watchdog = nil
        endRequest()
        stopEngine()
        updateState()
    }

    /// Pauses while the app talks, so it doesn't hear itself.
    func hold() {
        held = true
        heldSince = .now
        endRequest()
        updateState()
    }

    /// Picks up again once the app has finished talking.
    func resume() {
        held = false
        heldSince = nil
        lastActive = .now
        updateState()
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
        guard wanted, !held, allowed, let recognizer else { return }
        // Unavailable, say offline without the on-phone model: the watchdog tries again.
        guard recognizer.isAvailable else {
            updateState()
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        requestOnDevice = recognizer.supportsOnDeviceRecognition && preferOnDevice
        request.requiresOnDeviceRecognition = requestOnDevice
        request.contextualStrings = ["next step", "go back", "repeat", "start the timer", "yes", "no", "not now", "time left", "start watching"]
        generation += 1
        let current = generation
        transcript = ""
        requestStarted = .now
        lastActive = .now
        feed.set(request)
        task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler { [weak self] text, isFinal, failure in
            self?.received(text, isFinal: isFinal, failure: failure, generation: current)
        })
        restartTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.requestLifetime))
            guard let self, !Task.isCancelled, self.generation == current else { return }
            self.utteranceEnded()
        }
        updateState()
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

    private func received(_ text: String?, isFinal: Bool, failure: String?, generation current: Int) {
        guard current == generation else { return }
        if let text, !text.isEmpty {
            failures = 0
            transcript = text
            if isAppSpeaking?() == true, !held {
                // Heard over the app: its own words are left out when the utterance is
                // judged, and any the app isn't saying are the cook's, which cuts it short.
                let spoken = spokenText?()
                if spokenDuring == nil { spokenDuring = spoken }
                // "Mm", "uh huh", "okay" under the app's voice is listening, not a turn.
                let added = SelfEcho.newWords(in: text, spoken: spoken)
                if !added.isEmpty, !TurnTaking.isBackchannel(added) { bargeIn(spoken: spoken) }
            }
            if isFinal {
                utteranceEnded()
                return
            }
            // Judge the utterance once the cook stops talking: soon after a whole command,
            // later after one that trails off.
            let heard = spokenDuring.map { SelfEcho.strip(text, spoken: $0) } ?? text
            let pause = TurnTaking.pause(after: heard, screen: screen?() ?? .cook)
            pauseTimer?.cancel()
            pauseTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(pause))
                guard let self, !Task.isCancelled, self.generation == current else { return }
                self.utteranceEnded()
            }
        } else if let failure {
            // Recognition failed. Start again, backing off a little if it keeps failing.
            failures += 1
            report.errors += 1
            report.lastError = failure
            // Failing at once, twice in a row, means this kind of recognition isn't working
            // (on the phone: the speech model is missing; on Apple's servers: no network),
            // so try the other kind.
            let quick = Date.now.timeIntervalSince(requestStarted) < 2
            if quick, failures.isMultiple(of: 2), recognizer?.supportsOnDeviceRecognition == true {
                preferOnDevice = !requestOnDevice
            }
            restart(after: min(2.0, 0.5 * Double(failures)))
        } else if isFinal {
            // Recognition ended on its own after a quiet spell. Start again straight away;
            // backing off here left gaps of up to 5 seconds where nothing was heard.
            failures = 0
            restart(after: 0.1)
        }
    }

    private func restart(after delay: Double) {
        endRequest()
        let next = generation
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.generation == next, self.wanted, !self.held else { return }
            self.beginRequest()
        }
    }

    /// Acts on what was said, then starts a fresh request for the next utterance.
    private func utteranceEnded() {
        // Whatever recognition heard of the app's own voice is left out.
        let heardOverApp = spokenDuring != nil
        let text = spokenDuring.map { SelfEcho.strip(transcript, spoken: $0) } ?? transcript
        spokenDuring = nil
        endRequest()
        utterances += 1
        let speaking = isAppSpeaking?() == true
        // A backchannel under the app's voice, which is still going, didn't stop it and
        // isn't an answer either.
        let backchannel = heardOverApp && speaking && TurnTaking.isBackchannel(SelfEcho.words(in: text))
        // Keywords first: a clear short command acts at once, with no model to wait for.
        let command = backchannel ? nil : VoiceCommand.parse(text, screen: screen?() ?? .cook)
        if !text.isEmpty {
            report.heard = text
            report.outcome = backchannel ? "backchannel" : Self.outcome(of: text, command: command)
        }
        let sinceReply = speaking ? 0 : repliedAt.map { Date.now.timeIntervalSince($0) }
        if let command {
            handler?(command, text)
        } else if !backchannel, assistant.isAvailable, let context = assistantContext?() {
            switch AssistantGate.route(text, screen: screen?() ?? .cook, secondsSinceReply: sinceReply) {
            case .safety(let line):
                report.outcome = "food safety table"
                noteTurn("\"\(text)\": table, 0 ms")
                onAssistant?(CookAssistant.Reply(outcome: .answer(line), milliseconds: 0), text)
            case .model:
                askAssistant(text, context: context)
            case .command, .drop:
                break
            }
        } else if !backchannel, VoiceIntent.worthAsking(text),
                  TurnTaking.asksModel(wordCount: VoiceCommand.words(in: text).count, secondsSinceReply: sinceReply),
                  intentReader.isAvailable, let context = intentContext?() {
            readIntent(text, context: context)
        }
        // The command may have made the app talk, which holds listening until it's done.
        if wanted, !held { beginRequest() }
    }

    /// Asks the on-device model about words the keywords missed, while listening goes on.
    /// Its answer only does what saying that command does, and only if the cook hasn't
    /// said anything since and the step and the offer are still the ones it was asked about.
    private func readIntent(_ text: String, context: IntentContext) {
        let utterance = utterances
        report.outcome = "asking the model"
        Task { [weak self, intentReader] in
            let reading = await intentReader.read(text, context: context)
            guard let self else { return }
            let current = utterance == utterances && wanted
            let fits = intentContext?().map(context.stillApplies) ?? false
            let command = current && fits ? reading.intent.command : nil
            var line = "\"\(text)\": \(reading.intent.rawValue), \(reading.milliseconds) ms"
            if let problem = reading.problem {
                line += " (\(problem))"
            } else if reading.intent.command != nil, command == nil {
                line += " (dropped: things moved on)"
            }
            report.model = line
            if utterance == utterances { report.outcome = "model: \(reading.intent.rawValue)" }
            if let command { handler?(command, text) }
        }
    }

    /// Asks the assistant about words the keywords missed, while listening goes on. Its
    /// reply only counts if the cook hasn't said anything since and the recipe, step and
    /// offer are still the ones it was asked about.
    private func askAssistant(_ text: String, context: AssistantContext) {
        let utterance = utterances
        report.outcome = "asking the assistant"
        Task { [weak self, assistant] in
            let reply = await assistant.ask(text, context: context)
            guard let self else { return }
            let current = utterance == utterances && wanted
            let fits = assistantContext?().map(context.stillApplies) ?? false
            var line = "\"\(text)\": \(reply.summary), \(reply.milliseconds) ms"
            if !(current && fits) { line += " (dropped: things moved on)" }
            noteTurn(line)
            if utterance == utterances { report.outcome = "assistant: \(reply.summary)" }
            if current && fits { onAssistant?(reply, text) }
        }
    }

    /// Keeps the newest assistant turns for the debug panel.
    private func noteTurn(_ line: String) {
        report.model = line
        report.assistantTurns = Array(([line] + report.assistantTurns).prefix(Self.turnsShown))
    }

    /// "next", "ignored: 9 words" or "no command", for the debug panel.
    private static func outcome(of text: String, command: VoiceCommand?) -> String {
        if let command { return "\(command)" }
        let count = VoiceCommand.words(in: text).count
        return count > VoiceCommand.maximumWords ? "ignored: \(count) words" : "no command"
    }

    // MARK: Barge-in

    /// The microphone stayed loud for a quarter second: with the app's voice cancelled
    /// out, that's the cook. While the app is quiet it's just the kitchen.
    private func heardSpeechLevel() {
        guard wanted, !held, isAppSpeaking?() == true else { return }
        bargeIn(spoken: spokenText?())
    }

    private func bargeIn(spoken: String?) {
        if spokenDuring == nil { spokenDuring = spoken }
        report.bargeIns += 1
        onBargeIn?()
    }

    // MARK: Watchdog

    private func startWatchdog() {
        guard watchdog == nil else { return }
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.checkListening()
            }
        }
    }

    /// Once a second: whatever stopped listening, start it again.
    private func checkListening() {
        guard wanted else { return }
        if held {
            // Speech that ended without saying so would otherwise hold listening for good.
            if let heldSince, Date.now.timeIntervalSince(heldSince) > Self.watchdogDelay, isAppSpeaking?() == false {
                report.restarts += 1
                resume()
            }
            return
        }
        if task != nil {
            lastActive = .now
            return
        }
        guard Date.now.timeIntervalSince(lastActive) >= Self.watchdogDelay else { return }
        lastActive = .now
        report.restarts += 1
        if audio.isRunning {
            beginRequest()
        } else {
            restartEngine()
        }
        updateState()
    }

    private func updateState() {
        report.onDevice = requestOnDevice
        if !allowed {
            report.state = .noPermission
        } else if !wanted {
            report.state = .stopped
        } else if held {
            report.state = .paused
        } else if recognizer?.isAvailable != true {
            report.state = .unavailable
        } else if task != nil, audio.isRunning {
            report.state = .listening
        } else {
            report.state = .starting
        }
    }

    // MARK: Audio

    private func startEngine() -> Bool {
        guard allowed, recognizer != nil else { return false }
        audio.installTap(Self.tap(feeding: feed, gate: levelGate))
        guard audio.start() else {
            stopEngine()
            return false
        }
        if configurationObserver == nil {
            // Plugging in a display or headphones stops the engine; start it again.
            configurationObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.restartEngine() }
            }
        }
        return true
    }

    /// Takes the microphone off the engine. The engine itself keeps running for speech.
    private func stopEngine() {
        audio.removeTap()
        levelGate.reset()
    }

    /// The watchdog calls this again if the engine won't start.
    private func restartEngine() {
        guard wanted else { return }
        endRequest()
        stopEngine()
        audio.stop()
        // The session may have been switched off by an interruption.
        AudioSessionSetup.reset()
        guard startEngine() else {
            updateState()
            return
        }
        if !held { beginRequest() }
    }

    /// A phone call, Siri or an alarm stops the engine and switches the audio session off,
    /// and nothing started them again. Neither did a reset of the phone's audio.
    private func observeAudioSession() {
        guard sessionObservers.isEmpty else { return }
        let center = NotificationCenter.default
        sessionObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let began = type == AVAudioSession.InterruptionType.began.rawValue
            Task { @MainActor in self?.interrupted(began: began) }
        })
        sessionObservers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.mediaServicesReset() }
        })
    }

    private func interrupted(began: Bool) {
        if began {
            report.lastError = "Audio interrupted"
            endRequest()
            stopEngine()
            updateState()
        } else {
            restartEngine()
        }
    }

    /// Every audio object is gone after a reset, so the engine is built again.
    private func mediaServicesReset() {
        report.lastError = "Audio reset"
        endRequest()
        audio.rebuild()
        AudioSessionSetup.reset()
        restartEngine()
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

    nonisolated private static func tap(feeding feed: AudioFeed, gate: LevelGate) -> AVAudioNodeTapBlock {
        { buffer, _ in
            feed.append(buffer)
            gate.feed(level: AudioIO.level(of: buffer), at: ProcessInfo.processInfo.systemUptime)
        }
    }

    nonisolated private static func resultHandler(
        _ onResult: @escaping @MainActor (String?, Bool, String?) -> Void
    ) -> (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let nsError = error as NSError?
            // "No speech detected" only means the kitchen was quiet: a normal end, not a failure.
            let quiet = nsError?.domain == "kAFAssistantErrorDomain" && nsError?.code == 1110
            let isFinal = (result?.isFinal ?? false) || quiet
            let failure = quiet ? nil : nsError.map { "\($0.domain) \($0.code)" }
            Task { @MainActor in onResult(text, isFinal, failure) }
        }
    }
}

/// What listening is doing and what it last heard, for the debug panel.
struct VoiceReport: Equatable {
    enum State: String {
        case listening = "Listening"
        case paused = "Paused while speaking"
        case starting = "Starting"
        case stopped = "Stopped"
        case noPermission = "No permission"
        case unavailable = "Recognizer unavailable"
    }

    var state = State.stopped
    var heard: String?
    /// What became of `heard`: the command, "ignored: 9 words", "no command" or the model's answer.
    var outcome: String?
    /// The on-device model's last answer: what it heard, the intent and how long it took.
    var model: String?
    /// The assistant's last few turns, newest first: heard, tool or answer, milliseconds.
    var assistantTurns: [String] = []
    var restarts = 0
    var errors = 0
    /// Times the cook cut the app short by talking over it.
    var bargeIns = 0
    var lastError: String?
    var onDevice = false
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

/// Runs the speech detector on the audio thread and says once when speech starts.
private final class LevelGate: @unchecked Sendable {
    private let lock = NSLock()
    /// Only voice held this long stops the app; a shorter "mm" is left to its words.
    private var detector: SpeechDetector = {
        var detector = SpeechDetector()
        detector.holdSeconds = TurnTaking.bargeInHold
        return detector
    }()
    var onSpeech: (@Sendable () -> Void)?

    func feed(level: Double, at time: Double) {
        let started = lock.withLock { detector.feed(level: level, at: time) }
        if started { onSpeech?() }
    }

    func reset() {
        lock.withLock { detector.reset() }
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
        // Only counted as done once the session is on, so a failure is tried again.
        configured = (try? audio.setActive(true)) != nil
    }

    /// After an interruption or an audio reset the session is off; the next `configure()`
    /// sets it up again.
    static func reset() {
        configured = false
    }
}
