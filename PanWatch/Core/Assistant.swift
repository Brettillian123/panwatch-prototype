import Foundation

// The cooking assistant's pure parts: what reaches the on-device model, what it is told
// each turn, what its tools mean, and the rails its replies pass through before the app
// says them. The model itself lives in `Session/CookAssistant.swift`.
// Brett, Nov 4: "a little more conversational understanding similar to Alexa or a standard
// AI chatbot, obviously with heavy scope rails though." Research 16, sections 3 and 5.

/// What the app is showing when the cook asks, written out small for the model each turn.
struct AssistantContext: Equatable, Sendable {
    var recipe: String
    /// One-based.
    var stepNumber: Int
    var stepCount: Int
    var step: String
    /// The next step's instruction, nil on the last step.
    var nextStep: String?
    var ingredients: [String] = []
    var timers: [IntentContext.RunningTimer] = []
    /// The question waiting for a yes or no, if any.
    var offer: String?
    /// Every line of the recipe: its steps, spoken wording and ingredients. Not sent to the
    /// model; the rails check numbers in a reply against it.
    var facts: [String] = []

    /// At most this many ingredients, each cut to `ingredientLength` characters, so the
    /// context stays a small share of the model's 4096 tokens.
    static let ingredientLimit = 12
    static let ingredientLength = 60

    /// Fixed for the whole cook, so the session is made and warmed once.
    static let instructions = """
    You are the voice of a cooking app, talking with a cook whose hands are busy at the stove.
    Help only with: this recipe, its steps, ingredients and timers; general cooking technique; \
    substitutions; unit conversions; and the app's own controls. For anything else answer exactly: \
    \(AssistantRails.outOfScope)
    When the cook asks the app to do something, call one tool and add nothing.
    Otherwise answer in one or two short spoken sentences, with no lists.
    Never state a cooking time or temperature that is not in the recipe. \
    Never say food is done or safe; say what to check.
    If the words are not meant for the app, or you are unsure what was said, answer exactly: none
    """

    /// The prompt for one turn: the recipe, where the cook is, and the words heard.
    func prompt(heard: String) -> String {
        let shown = ingredients.prefix(Self.ingredientLimit).map { String($0.prefix(Self.ingredientLength)) }
        let running = timers.isEmpty
            ? "none"
            : timers.map { "\($0.label), \(IntentContext.spoken($0.secondsLeft)) left" }.joined(separator: "; ")
        return """
        Recipe: \(recipe), step \(stepNumber) of \(stepCount)
        Current step: \(step)
        Next step: \(nextStep ?? "none, this is the last step")
        Ingredients: \(shown.isEmpty ? "none listed" : shown.joined(separator: "; "))
        Running timers: \(running)
        Offer waiting: \(offer ?? "none")
        The cook said: "\(heard)"
        """
    }

    /// Whether a reply about `self` still fits the app `now`: the same recipe, step and offer.
    func stillApplies(to now: AssistantContext) -> Bool {
        recipe == now.recipe && stepNumber == now.stepNumber && offer == now.offer
    }
}

/// One thing the model's tools can ask the app to do. Each is a command the cook could
/// say, so it goes through the same handling: an offer still needs its yes, and starting
/// this step's timer while an offer waits accepts that offer.
enum AssistantAction: Equatable, Sendable {
    case next
    case back
    case goToStep(Int)
    case repeatStep
    case startOver
    case startStepTimer
    case setTimer(minutes: Int, name: String?)
    case cancelTimer(name: String?)
    case timeLeft
    case ingredients
    case showRecipes
    case chooseRecipe(String)
    case camera(on: Bool)
    /// Any other control the cook can name: help, voices, quiet, settings, yes, no.
    case app(HeardIntent)

    /// The tools, by name, as the model sees them: Apple's guidance is three to five.
    static let stepTool = "moveStep"
    static let timerTool = "timer"
    static let recipeTool = "recipe"
    static let appTool = "appControl"

    /// The `moveStep` tool's actions.
    static let stepActions = ["next", "previous", "goToStep", "repeatStep", "startOver"]
    /// The `timer` tool's actions.
    static let timerActions = ["startStepTimer", "set", "cancel", "timeLeft"]
    /// The `recipe` tool's actions.
    static let recipeActions = ["readIngredients", "openRecipes", "choose", "cameraOn", "cameraOff"]
    /// The `appControl` tool's commands: the model's old single-command answers, less the
    /// ones the other tools cover.
    static let appCommands: [HeardIntent] = HeardIntent.all.filter { intent in
        switch intent {
        case .voice(.none), .voice(.next), .voice(.back), .voice(.repeatStep), .voice(.startTimer),
             .voice(.timeLeft), .voice(.ingredients), .voice(.cancelTimer),
             .screen(.startOver), .screen(.showRecipes), .screen(.cameraOn), .screen(.cameraOff):
            return false
        default:
            return true
        }
    }

    /// The `moveStep` tool's call: nil when the action is unknown or the number is missing.
    static func step(_ action: String, number: Int?) -> AssistantAction? {
        switch action {
        case "next": .next
        case "previous": .back
        case "goToStep": number.map(AssistantAction.goToStep)
        case "repeatStep": .repeatStep
        case "startOver": .startOver
        default: nil
        }
    }

    /// The `timer` tool's call. A set timer needs its minutes; a blank name is no name.
    static func timer(_ action: String, minutes: Int?, name: String?) -> AssistantAction? {
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let named = name?.isEmpty == false ? name : nil
        switch action {
        case "startStepTimer": return .startStepTimer
        case "set": return minutes.flatMap { $0 > 0 ? .setTimer(minutes: $0, name: named) : nil }
        case "cancel": return .cancelTimer(name: named)
        case "timeLeft": return .timeLeft
        default: return nil
        }
    }

    /// The `recipe` tool's call. A dish must be one of the app's recipes.
    static func recipe(_ action: String, name: String?, titles: [String] = Recipe.all.map(\.title)) -> AssistantAction? {
        switch action {
        case "readIngredients": return .ingredients
        case "openRecipes": return .showRecipes
        case "choose": return name.flatMap { recipeTitle(for: $0, titles: titles) }.map(AssistantAction.chooseRecipe)
        case "cameraOn": return .camera(on: true)
        case "cameraOff": return .camera(on: false)
        default: return nil
        }
    }

    /// The `appControl` tool's call, by the command's name.
    static func app(_ name: String) -> AssistantAction? {
        appCommands.first { $0.rawValue == name }.map(AssistantAction.app)
    }

    /// The recipe the model named: the title itself, any two of its words, or the one dish
    /// with that word ("rice", "the chicken").
    static func recipeTitle(for name: String, titles: [String] = Recipe.all.map(\.title)) -> String? {
        if let exact = titles.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { return exact }
        let words = name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
        if let title = VoiceCommand.recipeTitle(in: words + ["make"], titles: titles) { return title }
        let dishes = Set(words.compactMap { VoiceCommand.dish(word: $0, titles: titles) })
        return dishes.count == 1 ? dishes.first : nil
    }

    /// Why the app can't do this here, said back to the model so it can tell the cook; nil
    /// when it can.
    func problem(in context: AssistantContext) -> String? {
        switch self {
        case .goToStep(let number) where !(1...max(1, context.stepCount)).contains(number):
            return "This recipe has \(context.stepCount) steps."
        case .next where context.nextStep == nil:
            return "This is the last step."
        case .back where context.stepNumber <= 1:
            return "This is the first step."
        case .setTimer(let minutes, _) where minutes > 24 * 60:
            return "Timers can run up to 24 hours."
        case .cancelTimer where context.timers.isEmpty, .timeLeft where context.timers.isEmpty:
            return "No timers are running."
        default:
            return nil
        }
    }

    /// The command the cook could have said for this, handled exactly as if they had. Nil
    /// only for a named timer, which the app starts with the name.
    var command: VoiceCommand? {
        switch self {
        case .next: .next
        case .back: .back
        case .goToStep(let number): .goToStep(number)
        case .repeatStep: .repeatStep
        case .startOver: .startOver
        case .startStepTimer: .startTimer
        case .setTimer(let minutes, let name): name == nil ? .setTimer(minutes: minutes) : nil
        case .cancelTimer(let name): name.map(VoiceCommand.cancelNamedTimer) ?? .cancelTimer
        case .timeLeft: .timeLeft
        case .ingredients: .ingredients
        case .showRecipes: .showRecipes
        case .chooseRecipe(let title): .makeRecipe(title)
        case .camera(let on): .camera(on: on)
        case .app(let intent): intent.command
        }
    }

    /// For the debug panel: "goToStep(3)", "setTimer 5 min pasta".
    var summary: String {
        switch self {
        case .setTimer(let minutes, let name): "setTimer \(minutes) min" + (name.map { " \($0)" } ?? "")
        case .cancelTimer(let name): "cancelTimer" + (name.map { " \($0)" } ?? "")
        case .app(let intent): intent.rawValue
        default: "\(self)"
        }
    }
}

/// Which way an utterance goes once the cook stops talking.
enum AssistantRoute: Equatable, Sendable {
    /// A keyword command: acts at once, no model.
    case command(VoiceCommand)
    /// A doneness or safety question: answered from `FoodSafety`, never the model.
    case safety(String)
    /// Worth asking the assistant.
    case model
    /// Not for the app: nothing happens.
    case drop
}

/// What reaches the assistant. Keywords go first and stay instant; long talk and talk that
/// isn't addressed to the app never reach the model.
enum AssistantGate {
    /// Longer than this is talk to the room. Higher than `VoiceIntent.maximumWords`, which
    /// the single-command model keeps, because a question takes more words than a command.
    static let maximumWords = 30

    /// Sounds, not words: "mmm uh".
    private static let hesitations: Set<String> = ["mm", "mmm", "hmm", "hm", "uh", "um", "er", "erm", "ah", "huh"]
    /// Said before what the cook means: "oh, how long...", "so what's next".
    private static let leadIns: Set<String> = ["oh", "so", "and", "okay", "ok", "well", "hey", "um", "uh", "alright", "right"]
    /// How words to the app begin: a question, or a request.
    private static let addressedStarts: Set<String> = [
        "what", "what's", "whats", "how", "how's", "hows", "can", "could", "is", "are", "does", "do", "did",
        "should", "shall", "will", "would", "which", "when", "why", "where", "who", "whose",
        "tell", "give", "set", "start", "cancel", "stop", "go", "read", "show", "open", "close", "turn",
        "switch", "skip", "repeat", "make", "let's", "lets", "convert", "substitute", "double", "halve",
        "any", "need", "i", "i'm", "im", "i've", "ive", "i'd", "id", "please", "remind", "help",
        "explain", "pause", "time", "timer", "next", "back", "previous",
        // Out of scope, but plainly said to the app: these get the one polite line.
        "write", "play", "ignore", "sing", "call", "find", "search", "look", "who's",
    ]

    static func route(_ text: String, screen: AppScreen = .cook, secondsSinceReply: Double?) -> AssistantRoute {
        if let command = VoiceCommand.parse(text, screen: screen) { return .command(command) }
        let counted = VoiceCommand.words(in: text)
        guard !counted.isEmpty, counted.count <= maximumWords else { return .drop }
        guard !counted.allSatisfy(hesitations.contains) else { return .drop }
        guard looksAddressed(text, wordCount: counted.count, secondsSinceReply: secondsSinceReply) else { return .drop }
        if let line = FoodSafety.answer(to: text) { return .safety(line) }
        return .model
    }

    /// Short words, words inside the follow-up window, or words that open like a question
    /// or a request. "Honey, can you grab the salt" and "oh that smells great" are the kitchen.
    static func looksAddressed(_ text: String, wordCount: Int, secondsSinceReply: Double?) -> Bool {
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
        // "And the salt?", "how about without butter?" carry on the last answer, so they
        // count only inside the follow-up window.
        if isContinuation(words) {
            return secondsSinceReply.map { $0 <= TurnTaking.followUpWindow } ?? false
        }
        if TurnTaking.asksModel(wordCount: wordCount, secondsSinceReply: secondsSinceReply) { return true }
        guard let first = words.first(where: { !leadIns.contains($0) }) else { return false }
        return addressedStarts.contains(first)
    }

    private static func isContinuation(_ words: [String]) -> Bool {
        guard let first = words.first else { return false }
        if first == "and" { return true }
        guard words.count > 1 else { return false }
        return ["how", "what"].contains(first) && ["about", "if"].contains(words[1])
    }
}

/// The rails every model reply passes before the app says it, in code as well as in the
/// instructions.
enum AssistantRails {
    /// About this many words at most; longer is cut at the sentence before the limit.
    static let maximumWords = 40
    static let outOfScope = "I can help with this recipe."
    /// Said in place of a reply that names a time or a temperature the recipe and the
    /// food-safety table don't have.
    static let unsure = "I'm not sure. Check the recipe or a thermometer."

    /// What the app says for `reply`, or nil for nothing ("none", or empty).
    static func check(_ reply: String, context: AssistantContext) -> String? {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        let bare = text.lowercased().filter { $0.isLetter }
        guard !bare.isEmpty, bare != "none" else { return nil }
        if claimsDone(text) { return FoodSafety.cannotTell }
        if !unsupportedNumbers(in: text, context: context).isEmpty { return unsure }
        return cut(text)
    }

    // MARK: Done

    private static let doneClaims = [
        "is done", "are done", "it's done", "its done", "they're done", "is ready", "are ready", "it's ready",
        "they're ready", "is cooked", "are cooked", "it's cooked", "cooked through", "fully cooked",
        "safe to eat", "is finished", "are finished",
    ]
    /// After a claim, these make it a check: "it's ready when the water is clear".
    private static let conditions = ["when", "once", "if", "after", "as soon"]

    /// Whether `text` says food is done, rather than what to check.
    static func claimsDone(_ text: String) -> Bool {
        let lower = " " + text.lowercased().replacingOccurrences(of: "\u{2019}", with: "'") + " "
        for claim in doneClaims {
            var search = lower.startIndex..<lower.endIndex
            while let found = lower.range(of: claim, range: search) {
                let after = lower[found.upperBound...].drop(while: { $0 == " " || $0 == "," })
                if !conditions.contains(where: { after.hasPrefix($0) }) { return true }
                search = found.upperBound..<lower.endIndex
            }
        }
        return false
    }

    // MARK: Times and temperatures

    private static let timeUnits: Set<String> = ["second", "seconds", "sec", "secs", "minute", "minutes", "min", "mins", "hour", "hours", "hr", "hrs"]
    private static let temperatureUnits: Set<String> = ["degree", "degrees", "f", "fahrenheit", "c", "celsius"]
    private static let joiners: Set<String> = ["to", "or", "and"]
    private static let wordNumbers: [String: Double] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40,
        "forty-five": 45, "fifty": 50, "sixty": 60, "ninety": 90,
    ]

    /// The numbers in `text` that are times or temperatures ("8 minutes", "350°F",
    /// "three to four minutes") and appear nowhere in the recipe, the food-safety table or
    /// the running timers.
    static func unsupportedNumbers(in text: String, context: AssistantContext) -> [Double] {
        let allowed = allowedNumbers(context)
        let tokens = Self.tokens(text)
        var found: [Double] = []
        for (index, token) in tokens.enumerated() {
            guard let value = number(token) else { continue }
            var next = index + 1
            while next < tokens.count, number(tokens[next]) != nil || joiners.contains(tokens[next]) { next += 1 }
            guard next < tokens.count, timeUnits.contains(tokens[next]) || temperatureUnits.contains(tokens[next]) else { continue }
            if !allowed.contains(value) { found.append(value) }
        }
        return found
    }

    /// Every number the recipe, the table and the timers give.
    static func allowedNumbers(_ context: AssistantContext) -> Set<Double> {
        var allowed = Set((FoodSafety.temperatures.union(FoodSafety.restMinutes)).map(Double.init))
        for line in context.facts + context.ingredients + [context.step] + [context.nextStep].compactMap({ $0 }) {
            for token in tokens(line) { if let value = number(token) { allowed.insert(value) } }
        }
        for timer in context.timers {
            let minutes = timer.secondsLeft / 60
            allowed.insert(Double(minutes))
            allowed.insert(Double((timer.secondsLeft + 59) / 60))
            allowed.insert(Double(timer.secondsLeft % 60))
        }
        return allowed
    }

    /// Lowercased words and numbers, with "°" as "degrees" and "350f" as "350 f".
    static func tokens(_ text: String) -> [String] {
        var spaced = ""
        var previous: Character?
        for character in text.lowercased() {
            if character == "\u{00B0}" {
                spaced += " degrees "
                previous = nil
                continue
            }
            if let previous, previous.isNumber != character.isNumber, previous.isLetter || character.isLetter {
                spaced += " "
            }
            spaced.append(character)
            previous = character
        }
        return spaced.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "." && $0 != "-" })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".-")) }
            .flatMap { $0.contains("-") && Double($0.split(separator: "-").first ?? "") != nil ? $0.split(separator: "-").map(String.init) : [$0] }
            .filter { !$0.isEmpty }
    }

    private static func number(_ token: String) -> Double? {
        Double(token) ?? wordNumbers[token]
    }

    // MARK: Length

    /// `text` cut at the last sentence that ends within `maximumWords` words; the first
    /// `maximumWords` words with a full stop when no sentence ends that soon.
    static func cut(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard words.count > maximumWords else { return text }
        var kept: [Substring] = []
        var lastEnd = 0
        for (index, word) in words.prefix(maximumWords).enumerated() {
            kept.append(word)
            if let last = word.last, ".!?".contains(last) { lastEnd = index + 1 }
        }
        if lastEnd > 0 { return kept.prefix(lastEnd).joined(separator: " ") }
        let joined = kept.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ",;:"))
        return joined + "."
    }
}
