import Foundation

/// The words of a timer offer in cook mode. Two kinds: the camera saw something go in
/// ("Looks like the pasta went in." / "Start a 9-minute timer?"), or a step with a plain
/// `timer` and no camera watch just opened ("This step takes 10 minutes." / "Start a
/// 10-minute timer?"). Either is only an offer: the timer starts on a tap or a "yes".
struct TimerOffer: Equatable, Sendable {
    let label: String
    let minutes: Int
    /// True for a step's plain timer; false for an offer after the camera saw an add.
    let plain: Bool
    /// The ingredient the camera saw; empty for a plain timer.
    var ingredient: String = ""

    /// The small line on the card.
    var caption: String {
        plain ? "This step takes \(minutes) \(minutes == 1 ? "minute" : "minutes")." : "Looks like the \(ingredient) went in."
    }

    /// The question on the card.
    var question: String { "Start a \(minutes)-minute timer?" }

    /// What is said aloud: the caption, then the question, with the number spoken plainly.
    var spoken: String { "\(caption) Start a \(minutes) minute timer?" }

    /// The camera's offer for a watched step.
    static func seen(_ watch: AdditionWatch) -> TimerOffer {
        TimerOffer(label: watch.timerLabel, minutes: watch.timerMinutes, plain: false, ingredient: watch.ingredient)
    }

    /// The offer when `step` opens: only a step with a plain timer and no camera watch,
    /// whose timer hasn't been started yet and isn't already running under its label.
    static func onOpen(_ step: RecipeStep, started: Bool, running labels: [String] = []) -> TimerOffer? {
        guard step.watch == nil, let timer = step.timer, !started,
              !labels.contains(where: { $0.caseInsensitiveCompare(timer.label) == .orderedSame }) else { return nil }
        return TimerOffer(label: timer.label, minutes: timer.minutes, plain: true)
    }

    /// The timer to start once the offer is taken, in the shape the cook's timers use.
    var watch: AdditionWatch {
        AdditionWatch(ingredient: ingredient, timerLabel: label, timerMinutes: minutes)
    }
}
