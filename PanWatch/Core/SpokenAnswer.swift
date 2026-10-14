import Foundation

/// A short spoken answer to the app's question, read from what speech recognition heard.
enum SpokenAnswer: Equatable, Sendable {
    case yes
    case no

    private static let yesWords: Set<String> = ["yes", "yeah", "yep", "yup", "sure", "okay", "ok", "start", "go"]
    private static let noWords: Set<String> = ["no", "nope", "cancel", "skip", "stop"]

    /// The answer in `text`, or nil if it holds neither. A "no" wins over a "yes", so
    /// "no, don't start it" never starts a timer. "Not now" counts as no.
    static func parse(_ text: String) -> SpokenAnswer? {
        let lower = text.lowercased()
        if lower.contains("not now") { return .no }
        let words = Set(lower.split(whereSeparator: { !$0.isLetter }).map(String.init))
        if !words.isDisjoint(with: noWords) { return .no }
        if !words.isDisjoint(with: yesWords) { return .yes }
        return nil
    }
}
