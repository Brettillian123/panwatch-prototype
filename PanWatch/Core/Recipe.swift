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
    /// The full wording read aloud; the screen shows `instruction`. Nil when they match.
    var spoken: String? = nil
}

extension RecipeStep {
    /// What the app reads aloud: the full wording when the screen shows a shortened one.
    var spokenText: String { spoken ?? instruction }
}

struct Recipe: Sendable {
    let title: String
    let steps: [RecipeStep]
    /// What to gather before starting, read aloud when the cook says "ingredients".
    var ingredients: [String] = []
    /// Start to plate, in minutes, counting the waits the steps name (boiling, timers, resting).
    var totalMinutes = 0
    /// How many people the amounts feed.
    var serves = 0
}

extension Recipe {
    /// Lists every recipe the app offers, in menu order.
    static let all: [Recipe] = [garlicButterPasta, rice, hardBoiledEggs, steamedBroccoli, oatmeal, panSearedChicken]

    /// The title in lowercase words joined by hyphens: "Hard-Boiled Eggs" is "hard-boiled-eggs".
    var slug: String {
        title.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: "-")
    }

    /// The name of the dish's photo in the asset catalog, "dish-<slug>".
    var photoName: String { "dish-" + slug }

    /// Where the recipe sits in `all`, for alternating tile colors; 0 for one not listed.
    var menuIndex: Int { Recipe.all.firstIndex(where: { $0.title == title }) ?? 0 }

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
        ],
        ingredients: ["1 pound of pasta", "1 tablespoon of salt", "3 tablespoons of butter", "4 cloves of garlic, minced"],
        totalMinutes: 20,
        serves: 4
    )

    /// Rice hides inside the pot from a phone on the counter, so a hand visit counts.
    static let rice = Recipe(
        title: "Rice",
        steps: [
            RecipeStep(id: 1, instruction: "Rinse 1 cup of long-grain white rice in a strainer.", watch: nil),
            RecipeStep(id: 2, instruction: "Bring 2 cups of water and 1/2 teaspoon of salt to a boil in a pot.", watch: nil),
            RecipeStep(
                id: 3,
                instruction: "Add the rice, stir once, cover, and turn the heat to low.",
                watch: AdditionWatch(ingredient: "rice", timerLabel: "Rice", timerMinutes: 18, minimumChange: 0)
            ),
            RecipeStep(
                id: 4,
                instruction: "Turn off the heat and let the rice rest, covered, for 5 minutes.",
                watch: nil,
                cue: StepCue(timerLabel: "Rice", secondsLeft: 0)
            ),
            RecipeStep(id: 5, instruction: "Fluff the rice with a fork and serve.", watch: nil),
        ],
        ingredients: ["1 cup of long-grain white rice", "2 cups of water", "1/2 teaspoon of salt"],
        totalMinutes: 30,
        serves: 3
    )

    /// The ice bath is called out two minutes early, so it's ready when the eggs are.
    static let hardBoiledEggs = Recipe(
        title: "Hard-Boiled Eggs",
        steps: [
            RecipeStep(id: 1, instruction: "Bring a large pot of water to a boil.", watch: nil),
            RecipeStep(
                id: 2,
                instruction: "Lower 4 eggs into the boiling water with a spoon.",
                // Eggs go in on a spoon and sink out of sight, so a hand visit counts.
                watch: AdditionWatch(ingredient: "eggs", timerLabel: "Eggs", timerMinutes: 12, minimumChange: 0)
            ),
            RecipeStep(
                id: 3,
                instruction: "Fill a bowl with ice and cold water.",
                watch: nil,
                cue: StepCue(timerLabel: "Eggs", secondsLeft: 120)
            ),
            RecipeStep(
                id: 4,
                instruction: "Move the eggs into the ice water for 5 minutes.",
                watch: nil,
                cue: StepCue(timerLabel: "Eggs", secondsLeft: 0)
            ),
            RecipeStep(id: 5, instruction: "Peel the eggs and serve.", watch: nil),
        ],
        ingredients: ["4 eggs", "a bowl of ice water"],
        totalMinutes: 25,
        serves: 2
    )

    /// Broccoli goes in by the handful and sits above the water, so it counts like pasta.
    static let steamedBroccoli = Recipe(
        title: "Steamed Broccoli",
        steps: [
            RecipeStep(id: 1, instruction: "Bring 1 inch of water to a boil in a pot with a steamer basket.", watch: nil),
            RecipeStep(
                id: 2,
                instruction: "Add 1 pound of broccoli florets to the basket and cover the pot.",
                watch: AdditionWatch(ingredient: "broccoli", timerLabel: "Broccoli", timerMinutes: 5, minimumChange: 0.02, countsRelease: true)
            ),
            RecipeStep(
                id: 3,
                instruction: "Toss the broccoli with 1 tablespoon of butter and a pinch of salt.",
                watch: nil,
                cue: StepCue(timerLabel: "Broccoli", secondsLeft: 0)
            ),
        ],
        ingredients: ["1 pound of broccoli florets", "1 tablespoon of butter", "a pinch of salt"],
        totalMinutes: 10,
        serves: 4
    )

    /// Oats are poured in and sink into the water, so a hand visit counts.
    static let oatmeal = Recipe(
        title: "Oatmeal",
        steps: [
            RecipeStep(id: 1, instruction: "Bring 2 cups of water and a pinch of salt to a boil.", watch: nil),
            RecipeStep(
                id: 2,
                instruction: "Stir in 1 cup of old-fashioned oats and turn the heat to medium-low.",
                watch: AdditionWatch(ingredient: "oats", timerLabel: "Oatmeal", timerMinutes: 5, minimumChange: 0)
            ),
            RecipeStep(
                id: 3,
                instruction: "Turn off the heat, cover, and let it sit for 2 minutes.",
                watch: nil,
                cue: StepCue(timerLabel: "Oatmeal", secondsLeft: 0)
            ),
            RecipeStep(id: 4, instruction: "Top with 1 tablespoon of brown sugar and serve.", watch: nil),
        ],
        ingredients: ["1 cup of old-fashioned oats", "2 cups of water", "a pinch of salt", "1 tablespoon of brown sugar"],
        totalMinutes: 10,
        serves: 2
    )

    /// The timer is for the first side only. Doneness comes from a thermometer, never the
    /// camera: USDA says color is not a safe sign for chicken.
    static let panSearedChicken = Recipe(
        title: "Pan-Seared Chicken",
        steps: [
            RecipeStep(
                id: 1,
                instruction: "Season 2 chicken breasts with 1/2 teaspoon salt, 1/4 teaspoon pepper.",
                watch: nil,
                spoken: "Season 2 boneless chicken breasts with 1/2 teaspoon of salt and 1/4 teaspoon of pepper."
            ),
            RecipeStep(id: 2, instruction: "Heat 1 tablespoon of oil in a pan over medium-high heat.", watch: nil),
            RecipeStep(
                id: 3,
                instruction: "Lay the chicken in the hot pan.",
                // A hand lets go of each piece, and a low pan shows them from the counter.
                watch: AdditionWatch(ingredient: "chicken", timerLabel: "Chicken", timerMinutes: 6, minimumChange: 0.02, countsRelease: true)
            ),
            RecipeStep(
                id: 4,
                instruction: "Flip and cook 6 more minutes, until a thermometer reads 165 °F.",
                watch: nil,
                cue: StepCue(timerLabel: "Chicken", secondsLeft: 0),
                spoken: "Flip the chicken and cook about 6 more minutes, until a thermometer reads 165 °F in the thickest part."
            ),
            RecipeStep(id: 5, instruction: "Let the chicken rest for 5 minutes before slicing.", watch: nil),
        ],
        ingredients: ["2 boneless chicken breasts", "1/2 teaspoon of salt", "1/4 teaspoon of pepper", "1 tablespoon of oil"],
        totalMinutes: 25,
        serves: 2
    )
}
