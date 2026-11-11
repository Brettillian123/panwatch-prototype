import Foundation
import Testing
@testable import PanWatchCore

/// The recipe checker: every rule in `Recipes/README.md` with an example that breaks it.
@Suite("Recipe rules")
struct RecipeRulesTests {
    /// A recipe that follows every rule; each test breaks one.
    private func soup(
        title: String = "Lentil Soup", method: CookMethod = .pot, serves: Int = 4, totalMinutes: Int = 40,
        items: [Ingredient]? = nil, steps: [RecipeStep]? = nil
    ) -> Recipe {
        Recipe(
            title: title, category: .soups, method: method,
            steps: steps ?? [
                RecipeStep(id: 1, instruction: "Bring 4 cups of water and 1/2 teaspoon of salt to a boil.", watch: nil),
                RecipeStep(id: 2, instruction: "Add 1 cup of lentils to the pot.",
                           watch: AdditionWatch(ingredient: "lentils", timerLabel: "Lentils", timerMinutes: 25, minimumChange: 0)),
                RecipeStep(id: 3, instruction: "Turn off the heat and serve.", watch: nil, cue: StepCue(timerLabel: "Lentils", secondsLeft: 0)),
            ],
            items: items ?? [
                Ingredient(name: "lentils", amount: "1 cup"), Ingredient(name: "water", amount: "4 cups"),
                Ingredient(name: "salt", amount: "1/2 teaspoon"),
            ],
            totalMinutes: totalMinutes, serves: serves
        )
    }

    private func step(_ id: Int, _ text: String, watch: AdditionWatch? = nil, spoken: String? = nil, timer: StepTimer? = nil) -> RecipeStep {
        RecipeStep(id: id, instruction: text, watch: watch, spoken: spoken, timer: timer)
    }

    private func steps(replacing index: Int, with replacement: RecipeStep) -> [RecipeStep] {
        var all = soup().steps
        all[index] = replacement
        return all
    }

    private func expectProblem(_ recipe: Recipe, mentioning text: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let problems = recipe.authoringProblems()
        #expect(problems.contains { $0.contains(text) }, "\(problems)", sourceLocation: sourceLocation)
    }

    @Test func theExampleIsClean() {
        #expect(soup().authoringProblems().isEmpty, "\(soup().authoringProblems())")
    }

    @Test func everyBundledFilePassesTheChecker() throws {
        #expect(RecipeBook.check(folder: BookPaths.sources) == [])
    }

    @Test func titleIsInTitleCase() {
        expectProblem(soup(title: "Lentil soup"), mentioning: "needs a capital")
        expectProblem(soup(title: "Soup With Lentils"), mentioning: "lowercase")
        #expect(RecipeRules.titleProblems("Chicken with Rice").isEmpty)
        #expect(RecipeRules.titleProblems("Hard-Boiled Eggs").isEmpty)
    }

    @Test func servesAndMinutesHaveLimits() {
        expectProblem(soup(serves: 0), mentioning: "\"serves\" must be 1 to 12")
        expectProblem(soup(serves: 13), mentioning: "\"serves\" must be 1 to 12")
        expectProblem(soup(totalMinutes: 0), mentioning: "1 to 240")
        expectProblem(soup(totalMinutes: 300), mentioning: "1 to 240")
        expectProblem(soup(totalMinutes: 20), mentioning: "less than its timers")
    }

    @Test func threeToTwelveSteps() {
        expectProblem(soup(steps: Array(soup().steps.prefix(2))), mentioning: "3 to 12 steps")
        let many = (1...13).map { step($0, "Stir the lentils.") }
        expectProblem(soup(steps: many), mentioning: "3 to 12 steps")
    }

    @Test func anInstructionFitsAndIsOneAction() {
        let long = "Add 1 cup of lentils to the pot, " + String(repeating: "stirring gently all the while ", count: 3) + "now."
        expectProblem(soup(steps: steps(replacing: 0, with: step(1, long))), mentioning: "at most 90")
        expectProblem(soup(steps: steps(replacing: 0, with: step(1, "Boil the water. Add the salt."))), mentioning: "one action")
        expectProblem(soup(steps: steps(replacing: 0, with: step(1, "Boil the water and salt"))), mentioning: "period")
    }

    @Test func aStepIsNeverOnlyAWait() {
        let all = soup().steps + [step(4, "Wait 10 minutes.")]
        expectProblem(soup(steps: all), mentioning: "only a wait")
        let rest = soup().steps + [step(4, "Let it rest for 5 minutes.")]
        expectProblem(soup(steps: rest), mentioning: "only a wait")
    }

    @Test func aStatedCookingTimeHasATimer() {
        let all = soup().steps + [step(4, "Simmer the salt for 10 minutes.")]
        expectProblem(soup(steps: all), mentioning: "no step has a 10-minute timer")
        let timed = soup().steps + [step(4, "Simmer the salt for 10 minutes.", timer: StepTimer(label: "Simmer", minutes: 10))]
        #expect(soup(totalMinutes: 60, steps: timed).authoringProblems().isEmpty)
        let resting = soup().steps + [step(4, "Let the salt rest off the heat for 10 minutes.")]
        // A wait off the heat needs its timer too.
        expectProblem(soup(steps: resting), mentioning: "no step has a 10-minute timer")
    }

    @Test func ingredientsUseUSUnitsAndAppearInASteps() {
        expectProblem(soup(items: soup().items + [Ingredient(name: "lentils", amount: "200 grams")]), mentioning: "US kitchen units")
        expectProblem(soup(items: soup().items + [Ingredient(name: "salt", amount: "")]), mentioning: "needs an amount")
        expectProblem(soup(items: soup().items + [Ingredient(name: "pepper", amount: "1/4 teaspoon")]), mentioning: "never named in a step")
        #expect(RecipeRules.amountProblem("1 1/2 cups") == nil)
        #expect(RecipeRules.amountProblem("2 large") == nil)
        #expect(RecipeRules.amountProblem("a pinch") == nil)
        #expect(RecipeRules.amountProblem("to taste") == nil)
        #expect(RecipeRules.amountProblem("some") != nil)
    }

    @Test func aWatchIsOnlyOnAStoveStepThatAddsSomething() {
        expectProblem(soup(method: .oven), mentioning: "only pot and pan recipes")
        expectProblem(soup(method: .noHeat), mentioning: "only pot and pan recipes")
        let stir = step(2, "Stir the lentils in the pot.", watch: AdditionWatch(ingredient: "lentils", timerLabel: "Lentils", timerMinutes: 25))
        expectProblem(soup(steps: steps(replacing: 1, with: stir)), mentioning: "adds something")
        let long = step(2, "Add 1 cup of lentils to the pot.", watch: AdditionWatch(ingredient: "lentils", timerLabel: "Lentils", timerMinutes: 121))
        expectProblem(soup(totalMinutes: 200, steps: steps(replacing: 1, with: long)), mentioning: "1 to 120 minutes")
    }

    @Test func plainWordsNoBrandsNoClaims() {
        expectProblem(soup(steps: steps(replacing: 2, with: step(3, "Turn off the heat; the model is done."))), mentioning: "plain word")
        expectProblem(soup(items: soup().items + [Ingredient(name: "Barilla lentils", amount: "1 cup")]), mentioning: "brand")
        expectProblem(soup(steps: steps(replacing: 2, with: step(3, "The soup is done, so serve it."))), mentioning: "never says food is done")
        expectProblem(soup(steps: steps(replacing: 2, with: step(3, "Serve when a thermometer reads 150 °F."))), mentioning: "150 °F")
        expectProblem(soup(steps: steps(replacing: 2, with: step(3, "Serve it at 70 °C."))), mentioning: "°F")
        #expect(RecipeRules.wordProblems("Cook until a thermometer reads 165 °F.").isEmpty)
        #expect(RecipeRules.wordProblems("Preheat the oven to 425 °F.").isEmpty)
        #expect(RecipeRules.wordProblems("Cook until the onions are soft.").isEmpty)
    }

    @Test func aCueNamesATimerFromAnEarlierStep() {
        let early = RecipeStep(id: 1, instruction: "Bring 4 cups of water and 1/2 teaspoon of salt to a boil.", watch: nil,
                               cue: StepCue(timerLabel: "Lentils", secondsLeft: 0))
        expectProblem(soup(steps: steps(replacing: 0, with: early)), mentioning: "no earlier step starts it")
    }

    @Test func theBookCheckNamesTheFileForEachProblem() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("book-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = BookPaths.sources
        let rice = try Data(contentsOf: source.appendingPathComponent("rice.json"))
        try rice.write(to: folder.appendingPathComponent("rice.json"))
        // The same title again under another id, a misnamed file, and a typo in a field.
        let copy = String(decoding: rice, as: UTF8.self).replacingOccurrences(of: "\"id\": \"rice\"", with: "\"id\": \"rice-two\"")
        try Data(copy.utf8).write(to: folder.appendingPathComponent("rice-two.json"))
        let typo = String(decoding: rice, as: UTF8.self)
            .replacingOccurrences(of: "\"id\": \"rice\"", with: "\"id\": \"plain-rice\"")
            .replacingOccurrences(of: "\"title\": \"Rice\"", with: "\"title\": \"Plain Rice\"")
            .replacingOccurrences(of: "\"serves\"", with: "\"servings\"")
        try Data(typo.utf8).write(to: folder.appendingPathComponent("rice-plain.json"))
        let lines = RecipeBook.check(folder: folder)
        #expect(lines.contains { $0.contains(": the title \"Rice\" is already used by rice") }, "\(lines)")
        #expect(lines.contains { $0.hasPrefix("rice-plain.json: unknown field \"servings\"") }, "\(lines)")
        #expect(lines.contains { $0.hasPrefix("rice-plain.json: missing \"serves\"") }, "\(lines)")
        #expect(lines.allSatisfy { $0.contains(".json: ") })
    }
}
