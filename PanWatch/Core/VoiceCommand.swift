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

    /// Longer utterances are conversation, not commands.
    static let maximumWords = 5

    private static let yesWords: Set<String> = ["yes", "yeah", "yep", "yup", "sure", "okay", "ok"]
    private static let noWords: Set<String> = ["no", "nope", "cancel", "stop"]
    /// Said around a command without changing it: "um, next step please".
    private static let fillerWords: Set<String> = ["please", "um", "uh", "hey", "now", "the"]

    /// The words that count toward `maximumWords`: everything said except filler.
    static func words(in text: String) -> [String] {
        allWords(in: text).filter { !fillerWords.contains($0) }
    }

    static func parse(_ text: String) -> VoiceCommand? {
        let spoken = allWords(in: text)
        // Filler is dropped before counting, so "okay, next step please" is still short.
        let words = spoken.filter { !fillerWords.contains($0) }
        guard !words.isEmpty, words.count <= maximumWords else { return nil }
        let set = Set(words)
        let phrase = words.joined(separator: " ")

        // Before the "no" words, because "cancel" and "stop" are among them.
        if set.contains("timer") && (set.contains("cancel") || set.contains("stop")) { return .cancelTimer }
        // Before the "yes" words, so "okay, that was it" marks rather than accepts an offer.
        if phrase.contains("that was it") || ["mark", "mark it", "mark that"].contains(phrase) { return .mark }
        // A "no" wins, so "no, don't start it" never starts a timer.
        // "Now" is filler, so "not now" is looked for in everything said.
        if spoken.joined(separator: " ").contains("not now") || !set.isDisjoint(with: noWords) { return .no }
        if phrase.contains("time left") || phrase.contains("how long") || phrase.contains("how much time")
            || phrase.contains("how much longer") { return .timeLeft }
        if set.contains("ingredients") || set.contains("ingredient") { return .ingredients }
        // Before "again", so "draw the pan again" draws rather than repeating the step.
        if set.contains("draw") || set.contains("redraw") || (set.contains("new") && set.contains("box"))
            || (set.contains("mark") && (set.contains("pan") || set.contains("box"))) { return .drawPan }
        if set.contains("repeat") || set.contains("again") { return .repeatStep }
        if set.contains("back") || set.contains("previous") { return .back }
        if set.contains("next") || set.contains("continue") { return .next }
        if set.contains("watching") || set.contains("watch") { return .startWatching }
        if set.contains("timer") { return .startTimer }
        if !set.isDisjoint(with: yesWords) || phrase == "start" || phrase == "start it" || phrase == "do it" {
            return .yes
        }
        return nil
    }

    private static func allWords(in text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init)
    }
}
