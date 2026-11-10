import Foundation

/// When the app talks on its own. The screen carries the information; the voice answers.
/// Brett, Nov 4: "Only when it matters": silent at launch; it speaks timer offers, "timer
/// done", and the steps a timer calls out; it reads a step only when the cook asks; after
/// an interruption it stays quiet until asked. Research 16, section 2, is the rest.

/// Three short sounds, made in code, in place of words when the screen already shows
/// the result.
enum Earcon: String, CaseIterable, Sendable {
    /// Heard and done.
    case acknowledged
    /// Heard, but there's nothing to do.
    case notUnderstood
    /// A timer finished.
    case timerDone
}

/// What made the step change.
enum StepSource: Sendable {
    /// The cook said "next", "back", "step three".
    case voice
    /// A tap on the screen: the cook is looking.
    case touch
    /// A volume button or Camera Control.
    case button
    /// A running timer reached the moment the recipe calls the step out.
    case timerCallOut
}

/// The moment the app might speak.
enum SpeechMoment: Equatable, Sendable {
    /// The app opened.
    case launch
    /// The app opened on a cook that was under way.
    case resume
    /// A recipe was picked.
    case recipeChosen(by: StepSource)
    case stepChanged(by: StepSource)
    /// The camera saw something go in; a timer is offered.
    case offer
    /// The app needs the cook to do something it didn't ask about: draw the pan box after
    /// the phone turned, the setup check's prompts.
    case guidance
    case timerDone
    /// The reply to what the cook just said, which needs words: a question, a time left,
    /// "there's no timer for this step".
    case answer
    /// Something failed. Spoken only when the cook just asked for something.
    case error(asked: Bool)
    /// A command did what was asked. Words only when the screen doesn't show the result.
    case confirmation(visible: Bool)
    /// A command was heard, but there's nothing for it to do here.
    case notUnderstood
}

/// What to do instead of, or with, the words.
enum SpeechAct: Equatable, Sendable {
    case silent
    case earcon(Earcon)
    case speak(String)
    case earconThenSpeak(Earcon, String)
}

/// The state the decision depends on. Times are seconds on any one clock.
struct SpeechState: Equatable, Sendable {
    var now: Double
    /// When the cook last cut the app off, if ever.
    var interruptedAt: Double?
    /// The app is saying something right now.
    var isSpeaking = false

    /// Within `SpeechPolicy.cooldown` of the cook cutting the app off.
    var inCooldown: Bool {
        guard let interruptedAt else { return false }
        return now - interruptedAt < SpeechPolicy.cooldown
    }
}

enum SpeechPolicy {
    /// After an interruption, nothing but the answer to what the cook said, for this long.
    static let cooldown = 1.5

    /// What to do at `moment`. `text` is the full line; `short` the brief one, where there is.
    static func act(_ moment: SpeechMoment, text: String, short: String? = nil, state: SpeechState) -> SpeechAct {
        switch moment {
        case .launch, .resume:
            return .silent
        case .recipeChosen(let source):
            return source == .voice ? .speak(short ?? text) : .silent
        case .stepChanged(let source):
            switch source {
            case .voice: return .earconThenSpeak(.acknowledged, text)
            case .touch, .button: return .silent
            // Time-critical, like a timer done: the timer's chime always plays, the words
            // only when the cook hasn't just cut the app off.
            case .timerCallOut: return state.inCooldown ? .earcon(.timerDone) : .earconThenSpeak(.timerDone, text)
            }
        case .offer, .guidance:
            // Said once, never queued: dropped if the app is talking or was just cut off.
            return unprompted(.speak(text), state: state)
        case .timerDone:
            // Time-critical: the chime always plays; the words wait for no one.
            return state.inCooldown ? .earcon(.timerDone) : .earconThenSpeak(.timerDone, text)
        case .answer:
            return .speak(text)
        case .error(let asked):
            return asked ? .speak(text) : .silent
        case .confirmation(let visible):
            return visible ? .earcon(.acknowledged) : .speak(text)
        case .notUnderstood:
            return .earcon(.notUnderstood)
        }
    }

    private static func unprompted(_ act: SpeechAct, state: SpeechState) -> SpeechAct {
        state.inCooldown || state.isSpeaking ? .silent : act
    }
}

/// Turn-taking: when the cook has finished, what stops the app, and how long it listens
/// after a reply. Research 16, section 2, rules 5 to 7.
enum TurnTaking {
    /// The pause that ends "next step": the command is complete.
    static let completePause = 0.5
    /// The pause that ends "how long do I...": the cook may go on.
    static let incompletePause = 1.2
    /// After the app answers, words the keywords miss still go to the model this long.
    static let followUpWindow = 5.0
    /// Voice this long, with the app's own voice cancelled out, stops the app; shorter is
    /// a backchannel ("mm", "uh huh") or a clatter, and its words decide.
    static let bargeInHold = 0.5

    /// Words a sentence doesn't end on: the cook is still talking.
    private static let trailingWords: Set<String> = [
        "the", "a", "an", "to", "for", "of", "and", "or", "but", "do", "i", "is", "it's", "my",
        "with", "in", "on", "at", "how", "what", "when", "which", "much", "many", "can", "should",
        "um", "uh", "so", "then", "like", "about", "if",
    ]

    /// `text` is a whole command: it parses, and doesn't trail off.
    static func isComplete(_ text: String, screen: AppScreen = .cook) -> Bool {
        let words = SelfEcho.words(in: text)
        guard let last = words.last, VoiceCommand.parse(text, screen: screen) != nil else { return false }
        return !trailingWords.contains(last)
    }

    /// How long a pause after `text` ends the utterance.
    static func pause(after text: String, screen: AppScreen = .cook) -> Double {
        isComplete(text, screen: screen) ? completePause : incompletePause
    }

    /// Sounds a listener makes under someone else's speech.
    private static let backchannelWords: Set<String> = [
        "mm", "mmm", "hmm", "mhm", "uh", "huh", "um", "uhhuh", "uh-huh", "mm-hm", "mm-hmm",
        "okay", "ok", "yeah", "yep", "yes", "right", "sure", "alright", "cool", "nice", "good", "oh", "ah",
    ]

    /// The cook's words heard over the app are only a backchannel: one or two listener
    /// sounds with no command, which mustn't stop the app.
    static func isBackchannel(_ newWords: [String]) -> Bool {
        let words = newWords.map { $0.lowercased() }
        guard !words.isEmpty, words.count <= 2 else { return false }
        if words.allSatisfy(backchannelWords.contains) { return true }
        // "Uh huh", "mm hm" come as two words.
        return words.joined(separator: " ") == "uh huh" || words.joined(separator: " ") == "mm hm"
    }

    /// Words the keywords missed go to the model only when they're short, or while the cook
    /// is plausibly still talking to the app: within the follow-up window after its reply.
    /// Longer talk out of the blue is the kitchen, not a command.
    static func asksModel(wordCount: Int, secondsSinceReply: Double?) -> Bool {
        if wordCount <= 3 { return true }
        guard let since = secondsSinceReply else { return false }
        return since <= followUpWindow
    }
}

extension Earcon {
    /// The tones, as (frequency in Hz, seconds).
    var tones: [(Double, Double)] {
        switch self {
        case .acknowledged: return [(880, 0.06), (1320, 0.08)]
        case .notUnderstood: return [(660, 0.08), (440, 0.12)]
        case .timerDone: return [(1047, 0.12), (1319, 0.12), (1568, 0.2)]
        }
    }

    /// Quiet: well under the voice, so it's a cue, not an alarm.
    static let amplitude: Float = 0.2

    /// Mono samples at `sampleRate`: each tone a sine with a short fade in and out so it
    /// never clicks, and a short gap between tones.
    func samples(sampleRate: Double) -> [Float] {
        let gap = Int(0.025 * sampleRate)
        var out: [Float] = []
        for (index, tone) in tones.enumerated() {
            let count = Int(tone.1 * sampleRate)
            let fade = max(1, Int(0.008 * sampleRate))
            for i in 0..<count {
                let edge = min(i, count - 1 - i)
                let envelope = edge < fade ? Float(edge) / Float(fade) : 1
                let phase = 2 * Double.pi * tone.0 * Double(i) / sampleRate
                out.append(Self.amplitude * envelope * Float(sin(phase)))
            }
            if index < tones.count - 1 { out += [Float](repeating: 0, count: gap) }
        }
        return out
    }
}
