import Testing
@testable import PanWatchCore

@Suite("Recipe check")
struct RecipeCheckTests {
    private let pasta = AdditionWatch(ingredient: "pasta", timerLabel: "Pasta", timerMinutes: 9)

    private func recipe(_ steps: [RecipeStep], title: String = "Test") -> Recipe {
        Recipe(title: title, steps: steps)
    }

    private func expectOneProblem(_ recipe: Recipe, mentioning text: String) {
        let problems = recipe.problems()
        #expect(problems.count == 1, "\(problems)")
        #expect(problems.first?.contains(text) == true, "\(problems)")
    }

    @Test func everyRecipeInTheAppIsClean() {
        for recipe in Recipe.all {
            #expect(recipe.problems().isEmpty, "\(recipe.title): \(recipe.problems())")
        }
    }

    @Test func noSteps() {
        expectOneProblem(recipe([]), mentioning: "no steps")
    }

    @Test func emptyTitle() {
        expectOneProblem(recipe([RecipeStep(id: 1, instruction: "Boil water.", watch: nil)], title: " "), mentioning: "no title")
    }

    @Test func idsOutOfOrder() {
        let steps = [
            RecipeStep(id: 1, instruction: "Boil water.", watch: nil),
            RecipeStep(id: 3, instruction: "Add salt.", watch: nil),
        ]
        expectOneProblem(recipe(steps), mentioning: "Step 3")
    }

    @Test func emptyInstruction() {
        expectOneProblem(recipe([RecipeStep(id: 1, instruction: "  ", watch: nil)]), mentioning: "Step 1: the instruction is empty")
    }

    @Test func zeroMinuteTimer() {
        let watch = AdditionWatch(ingredient: "pasta", timerLabel: "Pasta", timerMinutes: 0)
        expectOneProblem(recipe([RecipeStep(id: 1, instruction: "Add pasta.", watch: watch)]), mentioning: "at least 1 minute")
    }

    @Test func watchWithoutNames() {
        let watch = AdditionWatch(ingredient: "", timerLabel: "Pasta", timerMinutes: 9)
        expectOneProblem(recipe([RecipeStep(id: 1, instruction: "Add pasta.", watch: watch)]), mentioning: "ingredient and a timer name")
    }

    @Test func changeOutsideZeroToOne() {
        let watch = AdditionWatch(ingredient: "pasta", timerLabel: "Pasta", timerMinutes: 9, minimumChange: 1.5)
        expectOneProblem(recipe([RecipeStep(id: 1, instruction: "Add pasta.", watch: watch)]), mentioning: "between 0 and 1")
    }

    @Test func cueOnATimerNoEarlierStepStarts() {
        let steps = [
            RecipeStep(id: 1, instruction: "Drain.", watch: nil, cue: StepCue(timerLabel: "Pasta", secondsLeft: 0)),
            RecipeStep(id: 2, instruction: "Add pasta.", watch: pasta),
        ]
        expectOneProblem(recipe(steps), mentioning: "Step 1: the cue names timer \"Pasta\"")
    }

    @Test func cueWithNegativeTime() {
        let steps = [
            RecipeStep(id: 1, instruction: "Add pasta.", watch: pasta),
            RecipeStep(id: 2, instruction: "Drain.", watch: nil, cue: StepCue(timerLabel: "Pasta", secondsLeft: -5)),
        ]
        expectOneProblem(recipe(steps), mentioning: "negative")
    }

    @Test func cueLongerThanItsTimer() {
        let steps = [
            RecipeStep(id: 1, instruction: "Add pasta.", watch: pasta),
            RecipeStep(id: 2, instruction: "Melt butter.", watch: nil, cue: StepCue(timerLabel: "Pasta", secondsLeft: 600)),
        ]
        expectOneProblem(recipe(steps), mentioning: "only runs 540 s")
    }
}
