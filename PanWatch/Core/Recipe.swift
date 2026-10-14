import Foundation

/// What the camera should watch for during a step, and the timer to offer when it sees it.
struct AdditionWatch: Equatable, Sendable {
    /// Spoken in the prompt: "Looks like the pasta went in."
    let ingredient: String
    let timerLabel: String
    let timerMinutes: Int
    /// Share of the pan that must change for this step, when it should be less than the
    /// usual setting. Zero means a hand visiting the pan and leaving is enough, for
    /// ingredients too small to see once they're in, like minced garlic.
    var minimumChange: Double? = nil
    /// For ingredients carried in the hand, like a handful of pasta: the hand opening over
    /// the pot counts too, even when the pot hides the food from a phone on the counter.
    var countsRelease = false
}

/// When a step should be announced on its own: once the named timer has this much time
/// left. It lets the parts of a dish finish together, like the garlic butter being ready
/// just as the pasta is done.
struct StepCue: Equatable, Sendable {
    let timerLabel: String
    /// Seconds left on that timer. Zero means when it finishes.
    let secondsLeft: Int
}

struct RecipeStep: Identifiable, Equatable, Sendable {
    let id: Int
    let instruction: String
    /// Nil for steps where the camera stays out of it.
    let watch: AdditionWatch?
    /// Nil for steps the cook moves to whenever they're ready.
    var cue: StepCue? = nil
}

struct Recipe: Sendable {
    let title: String
    let steps: [RecipeStep]
}

extension Recipe {
    /// Two watched steps and three unwatched ones, so the demo shows the camera switching
    /// itself on and off as the recipe moves. Once the pasta timer runs, the butter, the
    /// garlic and the draining are each called out at the right moment.
    static let garlicButterPasta = Recipe(
        title: "Garlic Butter Pasta",
        steps: [
            RecipeStep(id: 1, instruction: "Bring 4 quarts of water and 1 tablespoon of salt to a boil.", watch: nil),
            RecipeStep(
                id: 2,
                instruction: "Add 1 pound of pasta to the boiling water.",
                // Pasta is big enough to see: it sticks out of the pot, or the hand holding
                // it opens over the pot. A hand that only visits isn't enough.
                watch: AdditionWatch(ingredient: "pasta", timerLabel: "Pasta", timerMinutes: 9, minimumChange: 0.02, countsRelease: true)
            ),
            RecipeStep(
                id: 3,
                instruction: "Melt 3 tablespoons of butter in a pan over medium heat.",
                watch: nil,
                cue: StepCue(timerLabel: "Pasta", secondsLeft: 180)
            ),
            RecipeStep(
                id: 4,
                instruction: "Add 4 cloves of minced garlic to the butter.",
                // Minced garlic is too small to see in the pan, so a hand visiting the pan is enough.
                watch: AdditionWatch(ingredient: "garlic", timerLabel: "Garlic", timerMinutes: 1, minimumChange: 0),
                cue: StepCue(timerLabel: "Pasta", secondsLeft: 90)
            ),
            RecipeStep(
                id: 5,
                instruction: "Drain the pasta and toss it in the garlic butter.",
                watch: nil,
                cue: StepCue(timerLabel: "Pasta", secondsLeft: 0)
            ),
        ]
    )
}
