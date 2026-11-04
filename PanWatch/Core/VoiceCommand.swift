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

    /// Longer utterances are conversation, not commands.
    static let maximumWords = 5

    private static let yesWords: Set<String> = ["yes", "yeah", "yep", "yup", "sure", "okay", "ok"]
    private static let noWords: Set<String> = ["no", "nope", "cancel", "stop"]

    static func parse(_ text: String) -> VoiceCommand? {
        let lower = text.lowercased()
        let words = lower.split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init)
        guard !words.isEmpty, words.count <= maximumWords else { return nil }
        let set = Set(words)
        let phrase = words.joined(separator: " ")

        // Before the "no" words, because "cancel" and "stop" are among them.
        if set.contains("timer") && (set.contains("cancel") || set.contains("stop")) { return .cancelTimer }
        // A "no" wins, so "no, don't start it" never starts a timer.
        if phrase.contains("not now") || !set.isDisjoint(with: noWords) { return .no }
        if phrase.contains("time left") || phrase.contains("how long") || phrase.contains("how much time")
            || phrase.contains("how much longer") { return .timeLeft }
        if set.contains("ingredients") || set.contains("ingredient") { return .ingredients }
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
}
