import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The cooking assistant: Apple's on-device model, for what the keywords miss. It answers
/// questions about this recipe in a sentence or two and runs the app's own controls
/// through tools, with numbers and names: "go to step four", "set a pasta timer for nine
/// minutes", "what can I use instead of butter?", then "how about oil?".
///
/// Private and offline. It needs iOS 26, Apple Intelligence on and an iPhone 15 Pro or
/// newer; anywhere else `isAvailable` is false and `IntentReader` with the keywords is all
/// there is, as before. The rails in `Core/Assistant.swift` check every reply.
@MainActor
final class CookAssistant {
    /// One turn's result, for acting on and for the debug panel.
    struct Reply: Sendable {
        enum Outcome: Sendable {
            /// A tool asked for one of the app's commands.
            case action(AssistantAction)
            /// Words to say, already through the rails.
            case answer(String)
            /// Not meant for the app.
            case silent
            /// The model took longer than `timeLimit`.
            case timedOut
            case failed(String)
        }
        let outcome: Outcome
        let milliseconds: Int

        /// "goToStep(3)", "answer: Use olive oil.", "timed out".
        var summary: String {
            switch outcome {
            case .action(let action): "tool \(action.summary)"
            case .answer(let line): "answer: \(line)"
            case .silent: "none"
            case .timedOut: "timed out"
            case .failed(let problem): "error: \(problem)"
            }
        }
    }

    /// Past this the cook has moved on: the "not understood" sound plays and nothing is said.
    static let timeLimit = Duration.seconds(4)
    /// After this long with no question, the next one starts a fresh conversation.
    static let quietReset: TimeInterval = 120
    /// A question and two follow-ups share a conversation; the fourth starts a fresh one,
    /// which keeps every turn well inside the model's 4096-token context.
    static let turnsPerConversation = 3

    #if canImport(FoundationModels)
    /// The session and its tools' inbox. Typed `Any` because the types only exist on iOS 26.
    private var conversation: Any?
    #endif
    private var recipe: String?
    private var turns = 0
    private var lastTurn: Date?

    /// Whether the model can be asked: iOS 26, Apple Intelligence on, the model downloaded.
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Makes and warms the session before the cook speaks. Call when listening starts.
    func prepare() {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            guard conversation == nil, isAvailable else { return }
            let made = Conversation()
            made.session.prewarm()
            conversation = made
            turns = 0
        }
        #endif
    }

    /// Lets the model go when listening stops.
    func release() {
        #if canImport(FoundationModels)
        conversation = nil
        #endif
        recipe = nil
        turns = 0
    }

    /// One turn: the words heard, with what the app shows. Only the first tool call acts;
    /// a reply with no tool call goes through the rails.
    func ask(_ heard: String, context: AssistantContext) async -> Reply {
        let start = ContinuousClock.now
        var outcome = Reply.Outcome.failed("model unavailable")
        #if canImport(FoundationModels)
        if #available(iOS 26, *), isAvailable {
            startFreshIfNeeded(for: context)
            prepare()
            if let current = conversation as? Conversation {
                turns += 1
                lastTurn = .now
                recipe = context.recipe
                current.inbox.begin(context)
                let result = await Self.respond(current.session, prompt: context.prompt(heard: heard))
                outcome = Self.outcome(of: result, inbox: current.inbox, context: context)
                if result.endsConversation {
                    // A late answer or an overflowing context: this session is done.
                    conversation = nil
                    prepare()
                }
            }
        }
        #endif
        let milliseconds = Int(((ContinuousClock.now - start) / .milliseconds(1)).rounded())
        return Reply(outcome: outcome, milliseconds: milliseconds)
    }

    /// A new recipe, two minutes of quiet or a used-up conversation start a fresh session.
    private func startFreshIfNeeded(for context: AssistantContext) {
        let quiet = lastTurn.map { Date.now.timeIntervalSince($0) > Self.quietReset } ?? false
        let newRecipe = recipe.map { $0 != context.recipe } ?? false
        guard newRecipe || quiet || turns >= Self.turnsPerConversation else { return }
        #if canImport(FoundationModels)
        conversation = nil
        #endif
        turns = 0
    }

    #if canImport(FoundationModels)
    /// What came back from one `respond`.
    private enum ModelResult: Sendable {
        case text(String)
        case timedOut
        case guardrail
        case overflow
        case error(String)

        var endsConversation: Bool {
            switch self {
            case .text, .guardrail: false
            case .timedOut, .overflow, .error: true
            }
        }
    }

    /// The model's reply, or `timedOut` once `timeLimit` passes, whichever comes first,
    /// without waiting for a slow reply to notice it was cancelled.
    @available(iOS 26, *)
    private static func respond(_ session: LanguageModelSession, prompt: String) async -> ModelResult {
        let (results, finish) = AsyncStream.makeStream(of: ModelResult.self)
        let answer = Task {
            do {
                let response = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.3))
                finish.yield(.text(response.content))
            } catch let error as LanguageModelSession.GenerationError {
                switch error {
                case .guardrailViolation: finish.yield(.guardrail)
                case .exceededContextWindowSize: finish.yield(.overflow)
                default: finish.yield(.error(error.localizedDescription))
                }
            } catch {
                finish.yield(.error(error.localizedDescription))
            }
        }
        let clock = Task {
            try? await Task.sleep(for: Self.timeLimit)
            finish.yield(.timedOut)
        }
        var first = results.makeAsyncIterator()
        let result = await first.next() ?? .timedOut
        answer.cancel()
        clock.cancel()
        finish.finish()
        return result
    }

    @available(iOS 26, *)
    private static func outcome(of result: ModelResult, inbox: ActionInbox, context: AssistantContext) -> Reply.Outcome {
        switch result {
        case .text(let text):
            if let action = inbox.action { return .action(action) }
            return AssistantRails.check(text, context: context).map(Reply.Outcome.answer) ?? .silent
        case .timedOut:
            return .timedOut
        case .guardrail:
            // The system's own guardrail stopped the question or the reply: out of scope.
            return .answer(AssistantRails.outOfScope)
        case .overflow:
            return .failed("context full")
        case .error(let problem):
            return .failed(problem)
        }
    }
    #endif
}

#if canImport(FoundationModels)
/// One conversation: the session, and the inbox its tools put their action in.
@available(iOS 26, *)
private final class Conversation {
    let inbox = ActionInbox()
    let session: LanguageModelSession

    init() {
        session = LanguageModelSession(
            model: .default,
            tools: [StepTool(inbox: inbox), TimerTool(inbox: inbox), RecipeTool(inbox: inbox), AppTool(inbox: inbox)],
            instructions: AssistantContext.instructions
        )
    }
}

/// Where the tools leave the one action of a turn. The app acts on it once the reply is
/// back and still fits, so a slow or stale reply changes nothing. Tools run off the main
/// actor, so a lock guards it.
@available(iOS 26, *)
final class ActionInbox: @unchecked Sendable {
    private let lock = NSLock()
    private var context: AssistantContext?
    private var taken: AssistantAction?

    /// A new turn about `context`, with no action yet.
    func begin(_ context: AssistantContext) {
        lock.withLock {
            self.context = context
            taken = nil
        }
    }

    var action: AssistantAction? { lock.withLock { taken } }

    /// Takes `action` for this turn and says back to the model what happened.
    func take(_ action: AssistantAction?) -> String {
        lock.withLock {
            guard let action else { return "The app can't do that." }
            if let context, let problem = action.problem(in: context) { return problem }
            guard taken == nil else { return "Only one thing at a time." }
            taken = action
            return "Done. The app tells the cook itself; reply with nothing."
        }
    }
}

@available(iOS 26, *)
struct StepTool: Tool {
    let name = AssistantAction.stepTool
    let description = "Moves through the recipe: next, previous, a step number, repeat this step, or start over."
    let inbox: ActionInbox

    @Generable
    enum Move {
        case next, previous, goToStep, repeatStep, startOver
    }

    @Generable
    struct Arguments {
        @Guide(description: "Where to go")
        let action: Move
        @Guide(description: "The step number, only for goToStep")
        let number: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        inbox.take(AssistantAction.step("\(arguments.action)", number: arguments.number))
    }
}

@available(iOS 26, *)
struct TimerTool: Tool {
    let name = AssistantAction.timerTool
    let description = "Timers: start this step's timer, set one for some minutes with a name, cancel one by name, or say the time left."
    let inbox: ActionInbox

    @Generable
    enum Use {
        case startStepTimer, set, cancel, timeLeft
    }

    @Generable
    struct Arguments {
        let action: Use
        @Guide(description: "Minutes, only for set")
        let minutes: Int?
        @Guide(description: "A short name like pasta, for set or cancel")
        let name: String?
    }

    func call(arguments: Arguments) async throws -> String {
        inbox.take(AssistantAction.timer("\(arguments.action)", minutes: arguments.minutes, name: arguments.name))
    }
}

@available(iOS 26, *)
struct RecipeTool: Tool {
    let name = AssistantAction.recipeTool
    let description = "Reads the ingredients aloud, opens the recipe list, chooses a recipe by name, or turns the camera on or off."
    let inbox: ActionInbox

    @Generable
    enum Use {
        case readIngredients, openRecipes, choose, cameraOn, cameraOff
    }

    @Generable
    struct Arguments {
        let action: Use
        @Guide(description: "The dish, only for choose")
        let name: String?
    }

    func call(arguments: Arguments) async throws -> String {
        inbox.take(AssistantAction.recipe("\(arguments.action)", name: arguments.name))
    }
}

@available(iOS 26, *)
struct AppTool: Tool {
    let name = AssistantAction.appTool
    let description = "Other app controls: yes or no to the offer, help, voices, quiet, talk, settings, details, close a menu."
    let inbox: ActionInbox

    /// Matches `AssistantAction.appCommands`, which a Core test keeps in step.
    @Generable
    enum Command {
        case yes, no, startWatching, whereAmI, clearDone, drawPan, switchCamera, showVoices, nextVoice
        case useThisVoice, useMyVoice, quiet, talk, stopListening, help, settings, details, done
    }

    @Generable
    struct Arguments {
        let command: Command
    }

    func call(arguments: Arguments) async throws -> String {
        inbox.take(AssistantAction.app("\(arguments.command)"))
    }
}
#endif
