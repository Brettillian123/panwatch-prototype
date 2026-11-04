import Foundation

/// Something the cook said to the app, read from what speech recognition heard.
///
/// Only short phrases count. Talking to someone in the kitchen, or presenting the app,
/// runs longer than a few words, so "and then I go back to the slides" is ignored while
/// "go back" on its own goes back a step.
enum VoiceCommand: Equatable, Sendable {
    case next
    case back
    case repeatStep
    /// "Yes", "sure", "okay": only answers the app's offer.
    case yes
    /// "No", "not now", "cancel": only answers the app's offer.
    case no
    /// "Start the timer": accepts the offer, or starts this step's timer without one.
    case startTimer
    case timeLeft
    /// "Start watching": confirms the pan box while it's being marked.
    case startWatching
    /// "Ingredients": reads what the recipe needs.
    case ingredients
    /// "Cancel the timer": removes the newest running timer.
    case cancelTimer
    /// "Draw a new box", "redraw": clears the screen to draw the pan box, at any time.
    case drawPan
    /// "That was it" or "mark": while practice is being recorded, marks the moment a real
    /// add happened, so the replay can score against it.
    case mark
    /// "Step three", "go to step 3": 1-based, as said.
    case goToStep(Int)
    /// "Where am I", "what step".
    case whereAmI
    /// "Start over", "from the top", "first step".
    case startOver
    /// "Set a timer for five minutes", "ten minute timer".
    case setTimer(minutes: Int)
    /// "Cancel the pasta timer": the words between "cancel" and "timer".
    case cancelNamedTimer(String)
    /// "Clear it", "got it": clears a timer that is done.
    case clearDone
    /// "Recipes", "what can I cook".
    case showRecipes
    /// "Make the rice", "let's do pasta": the title of the recipe, from `Recipe.all`.
    case makeRecipe(String)
    /// "Bigger", "left": moves the pan box while it's being drawn.
    case nudge(BoxNudge)
    /// "Turn off the camera" / "turn on the camera".
    case camera(on: Bool)
    /// "Use the front camera" (true), "use the back camera" (false), "switch camera" (nil).
    case switchCamera(toFront: Bool?)
    /// "Change the voice", "voices".
    case showVoices
    /// "Try Samantha", "hear Samantha"; nil for "try it", the highlighted voice.
    case tryVoice(String?)
    /// "Next voice": moves down the voice list and plays it.
    case nextVoice
    /// "Use Samantha", "use my voice", "use this one".
    case useVoice(VoicePick)
    /// "Be quiet", "mute".
    case quiet
    /// "Talk to me", "unmute".
    case talk
    /// "Stop listening": pauses the microphone for a while.
    case stopListening
    /// "What can I say", "help".
    case help
    /// "Settings".
    case settings
    /// "Show the details" (true), "hide the details" (false), "details" (nil, toggles).
    case details(show: Bool?)
    /// "Done", "close", "never mind": closes the open menu.
    case done
    /// "Record a practice" (true), "stop recording" (false).
    case recordPractice(Bool)
    // Setup check: "check the setup" runs the setup check again; "skip" ends one that is running.
    case checkSetup
    case skip

    /// Longer utterances are conversation, not commands.
    static let maximumWords = 6

    private static let yesWords: Set<String> = ["yes", "yeah", "yep", "yup", "sure", "okay", "ok"]
    private static let noWords: Set<String> = ["no", "nope", "cancel", "stop"]
    /// Said around a command without changing it: "um, next step please".
    private static let fillerWords: Set<String> = ["please", "um", "uh", "hey", "now", "the", "a", "for"]

    /// The words that count toward `maximumWords`: everything said except filler.
    static func words(in text: String) -> [String] {
        allWords(in: text).filter { !fillerWords.contains($0) }
    }

    /// What `text` asks for on `screen`. The screens only differ on the recipe menu, where
    /// one word of a single dish, like "rice" or "eggs", picks it.
    static func parse(_ text: String, screen: AppScreen = .cook) -> VoiceCommand? {
        let spoken = allWords(in: text)
        // Filler is dropped before counting, so "okay, next step please" is still short.
        let words = spoken.filter { !fillerWords.contains($0) }
        guard !words.isEmpty, words.count <= maximumWords else { return nil }
        if screen == .recipes, words.count == 1, let title = dish(word: words[0]) { return .makeRecipe(title) }
        let set = Set(words)
        let phrase = words.joined(separator: " ")
        // First, so "restart the recipe" restarts rather than opening the recipes. "Restart", "restart the recipe", "start over", "start again", "from the top".
        if (set.contains("restart") && !set.contains("timer")) || phrase.contains("start over")
            || phrase.contains("start again") || phrase.contains("begin again")
            || ["from top", "first step"].contains(phrase) { return .startOver }

        // Before the "no" words, because "cancel" and "stop" are among them.
        if let timerAt = words.firstIndex(where: { $0 == "timer" || $0 == "timers" }),
           let verbAt = words.firstIndex(where: { ["cancel", "stop", "clear", "delete"].contains($0) }), verbAt < timerAt {
            let name = words[(verbAt + 1)..<timerAt].filter { !["my", "that", "this", "it"].contains($0) }
            return name.isEmpty ? .cancelTimer : .cancelNamedTimer(name.joined(separator: " "))
        }
        if ["clear it", "got it", "clear"].contains(phrase) { return .clearDone }
        // Before the "yes" words, so "okay, that was it" marks rather than accepts an offer.
        if phrase.contains("that was it") || ["mark", "mark it", "mark that"].contains(phrase) { return .mark }
        // Phrases with "stop" in them that aren't a "no".
        if set.contains("listening") && (set.contains("stop") || set.contains("pause")) || phrase == "listen later" {
            return .stopListening
        }
        if phrase == "stop talking" { return .quiet }
        if phrase == "stop watching" { return .camera(on: false) }
        if set.contains("recording") && set.contains("stop") { return .recordPractice(false) }
        if phrase == "never mind" { return .done }
        // A "no" wins, so "no, don't start it" never starts a timer.
        // "Now" is filler, so "not now" is looked for in everything said.
        if spoken.joined(separator: " ").contains("not now") || !set.isDisjoint(with: noWords) { return .no }
        // Before "back" and "on", so "use the back camera" and "camera on" reach the camera.
        if set.contains("camera") {
            if set.contains("front") { return .switchCamera(toFront: true) }
            if set.contains("back") { return .switchCamera(toFront: false) }
            if set.contains("switch") || set.contains("flip") { return .switchCamera(toFront: nil) }
            if set.contains("off") { return .camera(on: false) }
            if set.contains("on") { return .camera(on: true) }
        }
        if phrase.contains("time left") || phrase.contains("how long") || phrase.contains("how much time")
            || phrase.contains("how much longer") { return .timeLeft }
        // Before "timer", so "ten minute timer" sets ten minutes rather than the step's timer.
        if let unit = words.firstIndex(where: { $0 == "minute" || $0 == "minutes" }),
           let minutes = number(in: Array(words[..<unit]), afterCue: true), (1...600).contains(minutes) {
            return .setTimer(minutes: minutes)
        }
        if set.contains("ingredients") || set.contains("ingredient") || phrase == "what do i need" { return .ingredients }
        // Setup check: before "again", so "check the setup again" checks.
        if set.contains("setup") || (set.contains("set") && set.contains("up")) { return .checkSetup }
        // "Skip to step five" goes to that step; "skip" or "skip this step" skips.
        if set.contains("skip") && !phrase.contains("to step") { return .skip }
        // Before "again", so "draw the pan again" draws rather than repeating the step.
        if set.contains("draw") || set.contains("redraw") || (set.contains("new") && set.contains("box"))
            || (set.contains("mark") && (set.contains("pan") || set.contains("box"))) { return .drawPan }
        if let voice = voiceCommand(words, set: set, phrase: phrase) { return voice }
        if ["be quiet", "quiet", "mute", "mute it"].contains(phrase) { return .quiet }
        if ["talk to me", "unmute", "speak", "speak up"].contains(phrase) { return .talk }
        if ["what can i say", "help", "help me", "commands"].contains(phrase) { return .help }
        if set.contains("settings") { return .settings }
        if set.contains("details") {
            return .details(show: set.contains("hide") ? false : set.contains("show") ? true : nil)
        }
        if set.contains("recipes") || set.contains("recipe") || phrase == "what can i cook" { return .showRecipes }
        if (set.contains("record") && set.contains("practice")) || phrase == "start recording" { return .recordPractice(true) }
        if ["done", "close", "close it", "close that", "close this", "all done", "i'm done"].contains(phrase) { return .done }
        if phrase.hasPrefix("where am i") || ((set.contains("what") || set.contains("which")) && set.contains("step")) {
            return .whereAmI
        }
        if let stepAt = words.firstIndex(of: "step"), let step = number(in: Array(words[(stepAt + 1)...]), afterCue: true) {
            return .goToStep(step)
        }
        if set.contains("repeat") || set.contains("again") || (set.contains("read") && set.contains("step")) { return .repeatStep }
        if set.contains("back") || set.contains("previous") { return .back }
        // Short, so "next time I'll use less salt" is talk; "okay next step please" still moves on.
        if phrase.contains("next step") || phrase == "go on"
            || (words.count <= 3 && (set.contains("next") || set.contains("continue"))) { return .next }
        if set.contains("watching") || set.contains("watch") { return .startWatching }
        // Short, so "turn left at the lights" is talk; "all right" is agreement, not a nudge.
        if words.count <= 3, !set.contains("all") {
            if set.contains("larger") { return .nudge(.bigger) }
            if let nudge = BoxNudge.allCases.first(where: { set.contains($0.rawValue) }) { return .nudge(nudge) }
        }
        if set.contains("timer") { return .startTimer }
        if let title = recipeTitle(in: words) { return .makeRecipe(title) }
        if !set.isDisjoint(with: yesWords) || phrase == "start" || phrase == "start it" || phrase == "do it" {
            return .yes
        }
        return nil
    }

    /// "Next voice", "change the voice", "try Samantha", "use my voice", "use this one".
    private static func voiceCommand(_ words: [String], set: Set<String>, phrase: String) -> VoiceCommand? {
        if phrase == "next voice" { return .nextVoice }
        if phrase == "use my voice" { return .useVoice(.mine) }
        if (set.contains("voice") || set.contains("voices"))
            && (set.contains("change") || set.contains("pick") || set.contains("choose") || words.count == 1) {
            return .showVoices
        }
        guard let first = words.first, words.count >= 2, words.count <= 4 else { return nil }
        let rest = words.dropFirst().filter { $0 != "voice" }
        let pointing: Set<String> = ["it", "this", "that", "one"]
        let isPointing = !rest.isEmpty && rest.allSatisfy { pointing.contains($0) }
        if first == "try" || first == "hear" {
            return .tryVoice(isPointing || rest.isEmpty ? nil : rest.joined(separator: " "))
        }
        if first == "use" && !rest.isEmpty {
            return .useVoice(isPointing ? .highlighted : .named(rest.joined(separator: " ")))
        }
        return nil
    }

    private static func allWords(in text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
    }

    // MARK: Numbers

    private static let units: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    private static let tens: [String: Int] = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60]

    /// The first number said in `words`, as digits ("3") or words ("twenty five"). After a
    /// cue like "step", recognition's "to" and "too" are heard as two.
    static func number(in words: [String], afterCue: Bool = false) -> Int? {
        for (index, word) in words.enumerated() {
            if let digits = Int(word) { return digits }
            if let ten = tens[word] {
                let unit = index + 1 < words.count ? units[words[index + 1]] ?? 0 : 0
                return ten + (unit < 10 ? unit : 0)
            }
            if let unit = units[word] { return unit }
            if afterCue && index == words.count - 1 && (word == "to" || word == "too") { return 2 }
        }
        return nil
    }

    // MARK: Recipes

    /// Words that ask for a dish: "make the rice", "let's do pasta", "cook the eggs".
    private static let choosingWords: Set<String> = ["make", "cook", "let's", "lets", "do"]

    /// The recipe named by any two words of its title, where a choosing word like "make"
    /// counts as one: "make the rice", "garlic butter pasta". Ordinary talk that mentions a
    /// dish, like "the pasta looks good", has one title word among other words, so it's nil.
    static func recipeTitle(in words: [String], titles: [String] = Recipe.all.map(\.title)) -> String? {
        let choosing = words.contains { choosingWords.contains($0) }
        let said = words.filter { !choosingWords.contains($0) }.map(stem)
        let scored = titles.map { title -> (title: String, matched: Int, other: Int) in
            let titleWords = Set(allWords(in: title).map(stem))
            let matched = Set(said.filter(titleWords.contains)).count
            let other = said.filter { !titleWords.contains($0) }.count
            return (title, matched, other)
        }
        guard let best = scored.max(by: { $0.matched < $1.matched }), best.matched > 0,
              best.matched + (choosing ? 1 : 0) >= 2, best.other <= 1,
              scored.filter({ $0.matched == best.matched }).count == 1 else { return nil }
        return best.title
    }

    /// The one dish whose title has `word` in it: "rice", "eggs", "oatmeal", "chicken",
    /// "broccoli", "pasta". Only the recipe menu listens for a single word, because
    /// anywhere else "the pasta looks good" is talk.
    static func dish(word: String, titles: [String] = Recipe.all.map(\.title)) -> String? {
        let said = stem(word)
        let having = titles.filter { allWords(in: $0).map(stem).contains(said) }
        return having.count == 1 ? having[0] : nil
    }

    /// "Eggs" and "egg" are the same dish.
    private static func stem(_ word: String) -> String {
        word.count > 3 && word.hasSuffix("s") ? String(word.dropLast()) : word
    }

    // MARK: Timers

    /// Whether "cancel the pasta timer" means the timer labelled `label`: every word said
    /// is in the label, with numbers said either way ("five minute" is "5 minute").
    static func timer(named name: String, matches label: String) -> Bool {
        func normalized(_ text: String) -> [String] {
            allWords(in: text).map { word in number(in: [word]).map(String.init) ?? stem(word) }
        }
        let labelWords = Set(normalized(label))
        let nameWords = normalized(name)
        return !nameWords.isEmpty && nameWords.allSatisfy(labelWords.contains)
    }
}

/// Which way "bigger", "left" and the rest change the pan box while it's drawn by voice.
enum BoxNudge: String, CaseIterable, Sendable {
    case bigger, smaller, left, right, up, down
}

/// Which voice "use ..." means.
enum VoicePick: Equatable, Sendable {
    case named(String)
    /// "Use my voice": the cook's Personal Voice.
    case mine
    /// "Use this one": the row highlighted in the voice menu.
    case highlighted
}

extension NormRect {
    /// A third of the frame in the middle: where a box drawn by voice starts.
    static let voiceStart = NormRect(x: 1.0 / 3, y: 1.0 / 3, width: 1.0 / 3, height: 1.0 / 3)

    /// Moved or resized by 10% of the frame, kept inside it. Sizes change around the centre.
    /// The frame is as the screen shows it (rotated and mirrored), so "left" is screen left.
    func nudged(_ nudge: BoxNudge) -> NormRect {
        let step = 0.1
        var box = self
        switch nudge {
        case .bigger, .smaller:
            let grow = nudge == .bigger ? step : -step
            let newWidth = min(1, max(0.08, width + grow))
            let newHeight = min(1, max(0.08, height + grow))
            box = NormRect(x: x + (width - newWidth) / 2, y: y + (height - newHeight) / 2, width: newWidth, height: newHeight)
        case .left: box.x -= step
        case .right: box.x += step
        case .up: box.y -= step
        case .down: box.y += step
        }
        box.x = min(max(0, box.x), 1 - box.width)
        box.y = min(max(0, box.y), 1 - box.height)
        return box
    }
}

/// What fills the screen: the cook screen, or a full-screen menu over it.
enum AppScreen: String, Sendable {
    case cook, recipes, settings, voices, help

    /// The three or four phrases that work right now, for the Say line. A moment on the
    /// cook screen (drawing, an offer, a done timer, no pan box) has its own.
    static func sayPhrases(
        screen: AppScreen, drawing: Bool = false, offer: Bool = false, timerDone: Bool = false,
        needsPan: Bool = false, canStartTimer: Bool = false, cameraOn: Bool = true, voiceName: String = "Samantha"
    ) -> [String] {
        switch screen {
        case .recipes: return ["make the rice", "let's do pasta", "done"]
        case .settings: return [cameraOn ? "turn off the camera" : "turn on the camera", "change the voice", "done"]
        case .voices: return ["try \(voiceName)", "use \(voiceName)", "next voice", "done"]
        case .help: return ["done"]
        case .cook:
            if drawing { return ["bigger", "smaller", "start watching", "cancel"] }
            if offer { return ["yes", "no", "not now"] }
            if timerDone { return ["clear it", "next step", "how long"] }
            if needsPan { return ["mark the pan", "next step"] }
            return ["next step", "repeat", canStartTimer ? "start the timer" : "how long", "what can I say"]
        }
    }
}
