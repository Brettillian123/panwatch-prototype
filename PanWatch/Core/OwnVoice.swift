import Foundation

/// The cook's own voice: Pocket TTS (Kyutai, CC-BY-4.0) speaking in a voice taken from a
/// short recording the cook makes of themselves. The recording and the voice made from it
/// are kept on this phone and never uploaded.
///
/// Safety, by design: the only way a voice gets made is a live recording from the
/// microphone, started inside `OwnVoiceFlow` after the cook has accepted `consentLine`.
/// There is no call anywhere in the app that takes an audio file, so the feature can't be
/// used to clone someone else from a clip. Kyutai's terms for Pocket TTS forbid cloning a
/// voice without explicit consent; this is how the app keeps to them.
enum OwnVoice {
    /// The voice id `Speaker` and the voice menu use for the cook's recorded voice.
    static let id = "own:mine"
    static let consentLine = "Record only your own voice. It stays on this phone."
    /// About 15 seconds read aloud at an easy pace. No command words, so nothing read
    /// here sounds like an answer to the app.
    static let script = """
        Tonight I'm making dinner at home. First I warm the pan and pour in a little oil. \
        The onions go in and soften until they turn golden. Then the garlic, a pinch of salt, \
        and a good stir. It smells wonderful already.
        """
    static let defaultName = "My voice"
    static let maxNameLength = 24
    /// A take shorter than this is too little to make a voice from.
    static let minSeconds = 8.0
    /// Recording stops by itself here.
    static let maxSeconds = 20.0
    /// Pocket TTS takes at most 10 seconds of a reference clip (FluidAudio
    /// `PocketTtsVoiceCloner.maxDurationSeconds`).
    static let cloneSeconds = 10.0
    /// Pocket TTS's rate, and the rate the recording is kept at.
    static let sampleRate = 24_000.0

    static func isOwn(_ id: String?) -> Bool { id == Self.id }

    /// The name as saved: trimmed, at most `maxNameLength` characters, never empty.
    static func cleanName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultName }
        return String(trimmed.prefix(maxNameLength)).trimmingCharacters(in: .whitespaces)
    }

    /// "Use my voice": the recorded voice once it exists, then the cook's Personal Voice,
    /// else nil (nothing of the cook's own to use yet).
    static func mine(recorded: Bool, personalID: String?) -> String? {
        recorded ? id : personalID
    }

    /// The voice that speaks for the recorded one while it's loading or if it fails: the
    /// one picked before it. Nil means the phone's best voice.
    static func fallback(previous: String?, current: String?) -> String? {
        isOwn(previous) ? current : previous
    }

    /// A meter reading from 0 to 1 for a microphone level (RMS, full scale 1): quiet room
    /// (-50 dB) at 0, a loud voice (-10 dB) at 1.
    static func meter(rms: Double) -> Double {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        return min(1, max(0, (decibels + 50) / 40))
    }

    /// The part of a take Pocket TTS is given: silence trimmed from both ends (20 ms
    /// windows under -40 dB), then the first `cloneSeconds`. Empty if nothing was said.
    static func cloneClip(_ samples: [Float], sampleRate: Double = sampleRate) -> [Float] {
        let window = max(1, Int(sampleRate * 0.02))
        let threshold: Float = 0.01
        func loud(_ start: Int) -> Bool {
            let end = min(samples.count, start + window)
            guard end > start else { return false }
            var sum: Float = 0
            for i in start..<end { sum += samples[i] * samples[i] }
            return (sum / Float(end - start)).squareRoot() >= threshold
        }
        var first = 0
        while first < samples.count, !loud(first) { first += window }
        guard first < samples.count else { return [] }
        var last = ((samples.count - 1) / window) * window
        while last > first, !loud(last) { last -= window }
        let end = min(samples.count, last + window)
        let limit = Int(sampleRate * cloneSeconds)
        return Array(samples[first..<min(end, first + limit)])
    }
}

/// What's kept about the cook's recorded voice, beside the recording itself.
struct SavedOwnVoice: Codable, Equatable, Sendable {
    var name: String
    var seconds: Double
    var recordedAt: Date
}

/// The recording flow, step by step. It can't finish without the consent line accepted
/// and a take this flow itself recorded from the microphone: `finish(take:)` takes only
/// the number `startRecording()` handed out for the latest take, so audio from anywhere
/// else has no way in.
struct OwnVoiceFlow: Equatable {
    enum Step: Equatable {
        /// The consent line is showing; nothing can be recorded yet.
        case consent
        /// Consent given; Record is offered.
        case ready
        case recording
        /// A long enough take: Listen back, Try again, or Keep.
        case recorded
        case done
    }

    enum Problem: Equatable {
        /// The take was under `OwnVoice.minSeconds`.
        case tooShort
    }

    private(set) var step: Step = .consent
    private(set) var problem: Problem?
    private(set) var consented = false
    /// Length of the latest take.
    private(set) var seconds: Double = 0
    /// Bumped by every take this flow starts.
    private(set) var take = 0

    mutating func acceptConsent() {
        guard step == .consent else { return }
        consented = true
        step = .ready
    }

    /// Starts a take and returns its number, or nil when consent hasn't been given or a
    /// take is already running.
    mutating func startRecording() -> Int? {
        guard consented, step == .ready || step == .recorded else { return nil }
        take += 1
        seconds = 0
        problem = nil
        step = .recording
        return take
    }

    /// Ends take `number` after `seconds`. A short take goes back to Record with a reason.
    mutating func stopRecording(take number: Int, seconds: Double) {
        guard step == .recording, number == take else { return }
        self.seconds = seconds
        if seconds < OwnVoice.minSeconds {
            problem = .tooShort
            step = .ready
        } else {
            step = .recorded
        }
    }

    /// Throws the take away and offers Record again.
    mutating func tryAgain() {
        guard consented, step == .recorded || step == .ready else { return }
        problem = nil
        seconds = 0
        step = .ready
    }

    var canFinish: Bool { consented && step == .recorded }

    /// Keeps take `number`; false unless it is this flow's latest finished take.
    mutating func finish(take number: Int) -> Bool {
        guard canFinish, number == take, take > 0 else { return false }
        step = .done
        return true
    }
}
