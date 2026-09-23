import Foundation

/// What the camera should watch for during a step, and the timer to offer when it sees it.
struct AdditionWatch: Equatable, Sendable {
    /// Spoken in the prompt: "Looks like the pasta went in."
    let ingredient: String
    let timerLabel: String
    let timerMinutes: Int
}

struct RecipeStep: Identifiable, Equatable, Sendable {
    let id: Int
    let instruction: String
    /// Nil for steps where the camera stays out of it.
    let watch: AdditionWatch?
}

struct Recipe: Sendable {
    let title: String
    let steps: [RecipeStep]
}

extension Recipe {
    /// Two watched steps and three unwatched ones, so the demo shows the camera switching
    /// itself on and off as the recipe moves.
    static let garlicButterPasta = Recipe(
        title: "Garlic Butter Pasta",
        steps: [
            RecipeStep(id: 1, instruction: "Bring a large pot of salted water to a boil.", watch: nil),
            RecipeStep(
                id: 2,
                instruction: "Add the pasta to the boiling water.",
                watch: AdditionWatch(ingredient: "pasta", timerLabel: "Pasta", timerMinutes: 9)
            ),
            RecipeStep(id: 3, instruction: "Melt 3 tablespoons of butter in a pan over medium heat.", watch: nil),
            RecipeStep(
                id: 4,
                instruction: "Add the minced garlic to the butter.",
                watch: AdditionWatch(ingredient: "garlic", timerLabel: "Garlic", timerMinutes: 1)
            ),
            RecipeStep(id: 5, instruction: "Drain the pasta and toss it in the garlic butter.", watch: nil),
        ]
    )
}
