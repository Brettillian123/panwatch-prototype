import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Reads what the cook meant from a whole sentence, like "I'm done with the butter,
/// what's next?", with Apple's on-device model, when the keywords in `VoiceCommand`
/// found nothing.
///
/// Private and offline. It needs iOS 26, Apple Intelligence turned on and an iPhone 15 Pro
/// or newer. Anywhere else `isAvailable` is false and the keywords are all there is.
@MainActor
final class IntentReader {
    /// One answer, for acting on and for the debug panel.
    struct Reading {
        /// `none` after a timeout or an error, so only an answer in time can act.
        let intent: HeardIntent
        let milliseconds: Int
        /// Why the answer is `none` without the model saying so: "timed out" or the error.
        let problem: String?
    }

    /// Past this the cook has moved on, so a later answer counts as `none`.
    static let timeLimit = Duration.seconds(2)

    #if canImport(FoundationModels)
    /// The session for the next utterance, made and warmed ahead so the model is loaded
    /// when the cook speaks. Typed `Any` because the type only exists on iOS 26.
    private var warmSession: Any?
    #endif

    /// Whether the model can be asked: iOS 26, Apple Intelligence on, the model downloaded.
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Loads the model and the instructions before the cook speaks. Call when listening starts.
    func prepare() {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            guard warmSession == nil, isAvailable else { return }
            let session = LanguageModelSession(instructions: IntentContext.instructions)
            session.prewarm()
            warmSession = session
        }
        #endif
    }

    /// Lets the model go when listening stops.
    func release() {
        #if canImport(FoundationModels)
        warmSession = nil
        #endif
    }

    /// Asks the model what `heard` means. Every utterance gets a fresh session, so earlier
    /// ones never pile up in the model's context, and the next one is warmed straight after.
    func read(_ heard: String, context: IntentContext) async -> Reading {
        let start = ContinuousClock.now
        var intent = HeardIntent.none
        var problem: String? = "model unavailable"
        #if canImport(FoundationModels)
        if #available(iOS 26, *), isAvailable {
            let session = warmSession as? LanguageModelSession
                ?? LanguageModelSession(instructions: IntentContext.instructions)
            warmSession = nil
            (intent, problem) = await Self.ask(session, prompt: context.prompt(heard: heard))
            prepare()
        }
        #endif
        let milliseconds = Int(((ContinuousClock.now - start) / .milliseconds(1)).rounded())
        return Reading(intent: intent, milliseconds: milliseconds, problem: problem)
    }

    #if canImport(FoundationModels)
    /// The model's answer, or `none` with the reason once `timeLimit` passes. Whichever
    /// comes first wins, without waiting for a slow answer to notice it was cancelled.
    @available(iOS 26, *)
    private static func ask(_ session: LanguageModelSession, prompt: String) async -> (HeardIntent, String?) {
        let (results, finish) = AsyncStream.makeStream(of: (HeardIntent, String?).self)
        let answer = Task {
            do {
                let response = try await session.respond(to: prompt, generating: ModelIntent.self)
                finish.yield((response.content.intent, nil))
            } catch {
                finish.yield((HeardIntent.none, "error: \(error.localizedDescription)"))
            }
        }
        let clock = Task {
            try? await Task.sleep(for: Self.timeLimit)
            finish.yield((HeardIntent.none, "timed out"))
        }
        var first = results.makeAsyncIterator()
        let result = await first.next() ?? (HeardIntent.none, "timed out")
        answer.cancel()
        clock.cancel()
        finish.finish()
        return result
    }
    #endif
}

#if canImport(FoundationModels)
/// What the model answers with: one of the app's commands, or none. The case names are
/// what the model reads, and match `VoiceIntent` and `ScreenIntent`.
@available(iOS 26, *)
@Generable(description: "The command the cook is asking the app for, or none if they are not speaking to the app")
enum ModelIntent {
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
    case none

    var intent: HeardIntent {
        switch self {
        case .next: .voice(.next)
        case .back: .voice(.back)
        case .repeatStep: .voice(.repeatStep)
        case .yes: .voice(.yes)
        case .no: .voice(.no)
        case .startTimer: .voice(.startTimer)
        case .timeLeft: .voice(.timeLeft)
        case .startWatching: .voice(.startWatching)
        case .ingredients: .voice(.ingredients)
        case .cancelTimer: .voice(.cancelTimer)
        case .whereAmI: .screen(.whereAmI)
        case .startOver: .screen(.startOver)
        case .clearDone: .screen(.clearDone)
        case .showRecipes: .screen(.showRecipes)
        case .drawPan: .screen(.drawPan)
        case .cameraOff: .screen(.cameraOff)
        case .cameraOn: .screen(.cameraOn)
        case .switchCamera: .screen(.switchCamera)
        case .showVoices: .screen(.showVoices)
        case .nextVoice: .screen(.nextVoice)
        case .useThisVoice: .screen(.useThisVoice)
        case .useMyVoice: .screen(.useMyVoice)
        case .quiet: .screen(.quiet)
        case .talk: .screen(.talk)
        case .stopListening: .screen(.stopListening)
        case .help: .screen(.help)
        case .settings: .screen(.settings)
        case .details: .screen(.details)
        case .done: .screen(.done)
        case .none: HeardIntent.none
        }
    }
}
#endif
