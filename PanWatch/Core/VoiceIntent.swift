import Foundation

/// What the on-device model decided the cook meant, for an utterance the keywords in
/// `VoiceCommand` didn't match, like "I'm done with the butter, what's next?".
///
/// The model answers with one of these names. `none` is everything not said to the app,
/// which is most of what a microphone in a kitchen hears.
enum VoiceIntent: String, CaseIterable, Sendable {
    case next
    case back
    case repeatStep
    case yes
    case no
    case startTimer
    case timeLeft
    case startWatching
    case ingredients
    case cancelTimer
    case none

    /// Longer than this is talk to the room, like presenting the app, so it never reaches
    /// the model.
    static let maximumWords = 16

    /// Whether `text` is worth asking the model about: something was said, and not a speech.
    static func worthAsking(_ text: String) -> Bool {
        let count = VoiceCommand.words(in: text).count
        return count > 0 && count <= maximumWords
    }

    /// The keyword command this stands for, so a model answer does exactly what saying
    /// that command does: an offer still needs a yes. Nil for `none`.
    var command: VoiceCommand? {
        switch self {
        case .next: .next
        case .back: .back
        case .repeatStep: .repeatStep
        case .yes: .yes
        case .no: .no
        case .startTimer: .startTimer
        case .timeLeft: .timeLeft
        case .startWatching: .startWatching
        case .ingredients: .ingredients
        case .cancelTimer: .cancelTimer
        case .none: nil
        }
    }

    /// What it means, for the model's list of commands.
    var meaning: String {
        switch self {
        case .next: "go on to the next step"
        case .back: "go back to the previous step"
        case .repeatStep: "read the current step again"
        case .yes: "accept the offer that is waiting"
        case .no: "turn down the offer that is waiting"
        case .startTimer: "start the timer for this step"
        case .timeLeft: "say how long the running timers have left"
        case .startWatching: "start watching the pan, once it has been marked"
        case .ingredients: "read what the recipe needs"
        case .cancelTimer: "cancel the newest running timer"
        case .none: "not meant for the app"
        }
    }
}

/// The commands for moving around the app, which the model can answer with beside
/// `VoiceIntent`'s, for phrasings the keywords miss, like "let's see what else I can make".
/// Commands that carry a number or a name ("step three", "use Samantha") stay keyword-only.
enum ScreenIntent: String, CaseIterable, Sendable {
    case whereAmI
    case startOver
    case clearDone
    case showRecipes
    case drawPan
    case cameraOff
    case cameraOn
    case switchCamera
    case showVoices
    case nextVoice
    case useThisVoice
    case useMyVoice
    case quiet
    case talk
    case stopListening
    case help
    case settings
    case details
    case done

    /// The keyword command this stands for.
    var command: VoiceCommand {
        switch self {
        case .whereAmI: .whereAmI
        case .startOver: .startOver
        case .clearDone: .clearDone
        case .showRecipes: .showRecipes
        case .drawPan: .drawPan
        case .cameraOff: .camera(on: false)
        case .cameraOn: .camera(on: true)
        case .switchCamera: .switchCamera(toFront: nil)
        case .showVoices: .showVoices
        case .nextVoice: .nextVoice
        case .useThisVoice: .useVoice(.highlighted)
        case .useMyVoice: .useVoice(.mine)
        case .quiet: .quiet
        case .talk: .talk
        case .stopListening: .stopListening
        case .help: .help
        case .settings: .settings
        case .details: .details(show: nil)
        case .done: .done
        }
    }

    /// What it means, for the model's list of commands.
    var meaning: String {
        switch self {
        case .whereAmI: "say which recipe and step the cook is on"
        case .startOver: "go back to the first step of the recipe"
        case .clearDone: "clear a timer that has finished ringing"
        case .showRecipes: "show the list of recipes to choose a different dish"
        case .drawPan: "draw the box around the pan again"
        case .cameraOff: "turn the camera off"
        case .cameraOn: "turn the camera on"
        case .switchCamera: "switch between the front and back camera"
        case .showVoices: "show the voices the app can speak in"
        case .nextVoice: "play the next voice in the voice list"
        case .useThisVoice: "choose the voice that was just played"
        case .useMyVoice: "speak in the cook's own Personal Voice"
        case .quiet: "stop speaking aloud"
        case .talk: "speak aloud again"
        case .stopListening: "stop listening to the microphone for two minutes"
        case .help: "say what the cook can say"
        case .settings: "open the settings"
        case .details: "show or hide the details panel"
        case .done: "close the menu that is open and go back to cooking"
        }
    }
}

/// One answer from the model: one of `VoiceIntent`'s, or one of `ScreenIntent`'s.
enum HeardIntent: Equatable, Sendable {
    case voice(VoiceIntent)
    case screen(ScreenIntent)

    static let none = HeardIntent.voice(.none)

    /// The name the model answered with.
    var rawValue: String {
        switch self {
        case .voice(let intent): intent.rawValue
        case .screen(let intent): intent.rawValue
        }
    }

    /// The keyword command this stands for; nil for `none`.
    var command: VoiceCommand? {
        switch self {
        case .voice(let intent): intent.command
        case .screen(let intent): intent.command
        }
    }

    /// Every name the model can answer with, `VoiceIntent`'s first.
    static let all: [HeardIntent] = VoiceIntent.allCases.map(HeardIntent.voice) + ScreenIntent.allCases.map(HeardIntent.screen)

    var meaning: String {
        switch self {
        case .voice(let intent): intent.meaning
        case .screen(let intent): intent.meaning
        }
    }
}

/// What the app is showing when the cook speaks, written out for the model so it can
/// tell "what's next?" from talk about dinner.
struct IntentContext: Equatable, Sendable {
    struct RunningTimer: Equatable, Sendable {
        let label: String
        let secondsLeft: Int
    }

    /// The current step's instruction.
    var step: String
    /// The question waiting for a yes or no, if any.
    var offer: String?
    var timers: [RunningTimer] = []

    /// Fixed for the whole cook, so it can be loaded once and kept warm.
    static let instructions: String = {
        let commands = HeardIntent.all.map { "- \($0.rawValue): \($0.meaning)" }
        return """
        You listen for a cook using a step-by-step cooking app, with their hands busy at the stove. \
        Each prompt is one thing the microphone heard, with what the app is showing.
        Pick the one command the cook is asking the app for.
        Answer none unless the cook is clearly speaking to the app. Talking to someone else, \
        thinking aloud, reading the recipe aloud or anything you are unsure of is none.
        Answer yes or no only when an offer is waiting and the cook is answering it.
        Commands:
        \(commands.joined(separator: "\n"))
        """
    }()

    /// The prompt for one utterance: the step, the offer, the timers and the words heard.
    func prompt(heard: String) -> String {
        let running = timers.isEmpty
            ? "none"
            : timers.map { "\($0.label), \(Self.spoken($0.secondsLeft)) left" }.joined(separator: "; ")
        return """
        Current step: \(step)
        Offer waiting: \(offer ?? "none")
        Running timers: \(running)
        The cook said: "\(heard)"
        """
    }

    /// Whether an answer about `self` still fits the app as it is `now`: the same step and
    /// the same offer. Timers keep counting, so they don't matter.
    func stillApplies(to now: IntentContext) -> Bool {
        step == now.step && offer == now.offer
    }

    /// "4 min 5 s", "40 s".
    static func spoken(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        guard seconds >= 60 else { return "\(seconds) s" }
        let rest = seconds % 60
        return rest == 0 ? "\(seconds / 60) min" : "\(seconds / 60) min \(rest) s"
    }
}
