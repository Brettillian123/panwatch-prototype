import Foundation
import Testing
@testable import PanWatchCore

/// The recipe checker: every rule in `Recipes/README.md` with an example that breaks it.
@Suite("Recipe rules")
struct RecipeRulesTests {
    /// A recipe that follows every rule; each test breaks one.
    private func soup(
        title: String = "Lentil Soup", method: CookMethod = .pot, serves: Int? = 4, totalMinutes: Int = 40,
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
        expectProblem(soup(serves: 0), mentioning: "\"serves\" must be 1 to 100")
        expectProblem(soup(serves: 101), mentioning: "\"serves\" must be 1 to 100")
        #expect(soup(serves: 100).authoringProblems().isEmpty)
        #expect(soup(serves: nil).authoringProblems().isEmpty, "a source that never says how many it feeds")
        expectProblem(soup(totalMinutes: 0), mentioning: "1 to 1440")
        expectProblem(soup(totalMinutes: 1_441), mentioning: "1 to 1440")
        #expect(soup(totalMinutes: 1_440).authoringProblems().isEmpty)
        expectProblem(soup(totalMinutes: 20), mentioning: "less than its timers")
    }

    @Test func threeToTwelveSteps() {
        expectProblem(soup(steps: Array(soup().steps.prefix(2))), mentioning: "3 to 20 steps")
        let many = (1...21).map { step($0, "Stir the lentils.") }
        expectProblem(soup(steps: many), mentioning: "3 to 20 steps")
        let twenty = soup().steps + (4...20).map { step($0, "Stir the lentils.") }
        #expect(soup(steps: twenty).authoringProblems().isEmpty, "\(soup(steps: twenty).authoringProblems())")
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
        let long = step(2, "Add 1 cup of lentils to the pot.", watch: AdditionWatch(ingredient: "lentils", timerLabel: "Lentils", timerMinutes: 481))
        expectProblem(soup(totalMinutes: 600, steps: steps(replacing: 1, with: long)), mentioning: "1 to 480 minutes")
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

    @Test func aPlainTimerRunsUpToEightHours() {
        let slow = { (minutes: Int) in
            self.soup(totalMinutes: 600, steps: self.soup().steps + [self.step(4, "Cook the soup on low in a slow cooker.", timer: StepTimer(label: "Slow", minutes: minutes))])
        }
        #expect(slow(480).authoringProblems().isEmpty, "\(slow(480).authoringProblems())")
        expectProblem(slow(481), mentioning: "a timer runs 1 to 480 minutes")
        expectProblem(soup(totalMinutes: 500, steps: slow(480).steps), mentioning: "less than its timers")
    }

    @Test func aRangeIsCoveredByATimerOnItsLowerNumber() {
        let ranged = step(2, "Add 1 cup of lentils to the pot.", watch: AdditionWatch(ingredient: "lentils", timerLabel: "Lentils", timerMinutes: 25, minimumChange: 0),
                          spoken: "Add the lentils and simmer 25 to 30 minutes, until soft.")
        #expect(soup(steps: steps(replacing: 1, with: ranged)).authoringProblems().isEmpty)
        let hyphen = step(2, "Add 1 cup of lentils and simmer 25-30 minutes.", watch: AdditionWatch(ingredient: "lentils", timerLabel: "Lentils", timerMinutes: 25, minimumChange: 0))
        #expect(soup(steps: steps(replacing: 1, with: hyphen)).authoringProblems().isEmpty)
        let hours = step(4, "Cook the soup on low for 6 to 8 hours.", timer: StepTimer(label: "Slow", minutes: 360))
        #expect(soup(totalMinutes: 600, steps: soup().steps + [hours]).authoringProblems().isEmpty)
        // Neither number has a timer: still a problem, naming the upper one.
        let neither = soup().steps + [step(4, "Simmer the salt for 7 to 10 minutes.")]
        expectProblem(soup(steps: neither), mentioning: "it says 10 minutes")
    }

    @Test func secondsNeedNoTimer() {
        #expect(RecipeRules.statedTimes(in: "Microwave for 30 seconds.").isEmpty)
        #expect(RecipeRules.statedTimes(in: "Stir for 1/2 minute.").isEmpty)
        #expect(RecipeRules.statedMinutes(in: "Microwave for 120 seconds.") == [2])
        let quick = soup().steps + [step(4, "Microwave the salt for 30 seconds.")]
        #expect(soup(steps: quick).authoringProblems().isEmpty)
    }

    @Test func everydayUnitsAndAFew() {
        for amount in ["1 cube", "2 cubes", "a dash", "3 dashes", "a few dashes", "a couple of sprigs", "2 stalks", "1 head",
                       "4 slices", "2 sticks", "3 strips", "1 wedge", "a handful", "1 bunch", "1 can", "1 jar", "1 bottle",
                       "1 packet", "1 envelope", "5 drops", "2 ears", "2 fillets", "4 breasts", "6 thighs", "1 rib",
                       "4 links", "2 sheets", "8 pieces", "a pinch"] {
            #expect(RecipeRules.amountProblem(amount) == nil, "\(amount)")
        }
        #expect(RecipeRules.amountProblem("a few") != nil)
        #expect(RecipeRules.amountProblem("a few grams") != nil)
    }

    @Test func aSourceMayCreditAProgram() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("credit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let rice = String(decoding: try Data(contentsOf: BookPaths.sources.appendingPathComponent("rice.json")), as: UTF8.self)
        let credited = rice.replacingOccurrences(of: "\"name\": \"Sous Vision\"",
                                                 with: "\"name\": \"Sous Vision\", \"credit\": \"Healthy Kitchen Program\"")
        #expect(credited != rice)
        try Data(credited.utf8).write(to: folder.appendingPathComponent("rice.json"))
        #expect(RecipeBook.check(folder: folder) == [])
        guard case .success(let recipe) = RecipeBook.decode(Data(credited.utf8)) else { Issue.record("no decode"); return }
        #expect(recipe.source.credit == "Healthy Kitchen Program")
        #expect(RecipeEntry(recipe, hasPhoto: false).credit == "Healthy Kitchen Program")
    }

    @Test func creditsGroupEachSourcesProgramsOnce() {
        let entry = { (id: String, credit: String?) in
            RecipeEntry(id: id, title: id, category: .soups, method: .pot, totalMinutes: 20, serves: nil,
                        ingredients: [], source: "MyPlate", credit: credit, hasPhoto: false)
        }
        let notices = Credits.recipeNotices([entry("a", "Program One"), entry("b", "Program Two"), entry("c", "Program One"), entry("d", nil)],
                                            sources: [RecipeSourceCredit(name: "MyPlate", credit: "Recipes adapted from MyPlate.", url: "https://example.org/")])
        #expect(notices.count == 1)
        #expect(notices.first?.text == "Recipes adapted from MyPlate.\nhttps://example.org/\nProgram One\nProgram Two")
    }

    @Test func anIngredientsMainNameDropsParentheses() {
        #expect(RecipeRules.mainName("tomatoes (canned), drained") == "tomatoes")
        #expect(RecipeRules.mainName("chicken broth (low sodium)") == "chicken broth")
        #expect(RecipeRules.isUsed("crushed tomatoes (28 ounces), undrained", in: "Pour in the crushed tomatoes."))
    }

    @Test func titleCaseKeepsSmallWordsLowercase() {
        #expect(RecipeRules.titleProblems("Dulce de Leche").isEmpty)
        #expect(RecipeRules.titleProblems("Arroz con Pollo").isEmpty)
        #expect(RecipeRules.titleProblems("Chicken as a Main").isEmpty)
        #expect(!RecipeRules.titleProblems("Dulce De Leche").isEmpty)
        #expect(RecipeRules.titleProblems("De Gallo Salsa").isEmpty, "the first word keeps its capital")
    }

    @Test func aCueMayNameAnEarlierPlainTimer() {
        let bake = [
            step(1, "Preheat the oven to 400 °F."),
            step(2, "Bake the lentils for 25 minutes.", timer: StepTimer(label: "Bake", minutes: 25)),
            RecipeStep(id: 3, instruction: "Warm the salt in a bowl.", watch: nil, cue: StepCue(timerLabel: "Bake", secondsLeft: 300)),
            RecipeStep(id: 4, instruction: "Serve the lentils with the water.", watch: nil, cue: StepCue(timerLabel: "Bake", secondsLeft: 0)),
        ]
        let recipe = soup(method: .oven, steps: bake)
        #expect(recipe.authoringProblems().isEmpty, "\(recipe.authoringProblems())")
        let tooLong = [bake[0], bake[1], RecipeStep(id: 3, instruction: "Warm the salt in a bowl.", watch: nil, cue: StepCue(timerLabel: "Bake", secondsLeft: 2_000)), bake[3]]
        expectProblem(soup(method: .oven, steps: tooLong), mentioning: "which only runs")
    }

    @Test func oneActionMeansTwoCommandsNotTwoSentences() {
        #expect(RecipeRules.hasTwoActions("Boil the water. Add the salt."))
        #expect(RecipeRules.hasTwoActions("Stir the sauce; season it."))
        #expect(!RecipeRules.hasTwoActions("Cook the onions until soft. They should be golden at the edges."))
        #expect(!RecipeRules.hasTwoActions("Add 1.5 cups of water."))
        let look = step(1, "Bring the water and salt to a boil. Big bubbles should break the top.")
        #expect(soup(steps: steps(replacing: 0, with: look)).authoringProblems().isEmpty)
    }

    @Test func aTemperatureIsASettingOrAMeasureNeverAClaim() {
        for text in ["Bake at 350 °F for 25 minutes.", "Heat the oven to 400 °F.", "Heat the oil to 350 °F.",
                     "Bake at 400 degrees until golden.", "Preheat the oven to 425 °F.", "Roast at 450 °F.",
                     "Cook until a thermometer reads 165 °F.", "Heat the oil until a thermometer reads 350 °F."] {
            #expect(RecipeRules.wordProblems(text).isEmpty, "\(text): \(RecipeRules.wordProblems(text))")
        }
        for text in ["The chicken is now 165 °F.", "It is 400 degrees, so serve it.", "Serve when a thermometer reads 150 °F.",
                     "Cook the chicken to 150 °F.", "The soup is done."] {
            #expect(!RecipeRules.wordProblems(text).isEmpty, "\(text)")
        }
        let bake = soup(method: .oven, steps: [
            step(1, "Preheat the oven to 350 °F."),
            step(2, "Bake the lentils at 350 °F for 25 minutes.", timer: StepTimer(label: "Bake", minutes: 25)),
            step(3, "Serve the lentils with the water and salt."),
        ])
        #expect(bake.authoringProblems().isEmpty, "\(bake.authoringProblems())")
    }

    @Test func aFractionalTimeNeedsNoTimer() {
        #expect(RecipeRules.statedTimes(in: "Stir for 1 1/2 minutes.").isEmpty)
        #expect(RecipeRules.statedTimes(in: "Microwave for 90 seconds.").isEmpty)
        let quick = soup().steps + [step(4, "Stir the salt for 1 1/2 minutes.")]
        #expect(soup(steps: quick).authoringProblems().isEmpty)
    }

    @Test func timesReadInHoursPastAnHour() {
        #expect(Recipe.timeText(minutes: 25) == "25 min")
        #expect(Recipe.timeText(minutes: 90) == "1 hr 30 min")
        #expect(Recipe.timeText(minutes: 480) == "8 hr")
        #expect(Recipe.spokenTime(minutes: 61) == "1 hour 1 minute")
        let noServes = RecipeEntry(id: "x", title: "X", category: .soups, method: .pot, totalMinutes: 25, serves: nil,
                                   ingredients: [], source: "Sous Vision", hasPhoto: false)
        #expect(noServes.summary == "25 min")
        let serves = RecipeEntry(id: "y", title: "Y", category: .soups, method: .pot, totalMinutes: 90, serves: 14,
                                 ingredients: [], source: "Sous Vision", hasPhoto: false)
        #expect(serves.summary == "1 hr 30 min · Serves 14")
    }

    @Test func aLongTimerIsOfferedInHours() {
        let six = TimerOffer(label: "Slow", minutes: 360, plain: true)
        #expect(six.question == "Start a 6-hour timer?")
        #expect(six.caption == "This step takes 6 hours.")
        #expect(six.spoken == "This step takes 6 hours. Start a 6 hour timer?")
        #expect(TimerOffer(label: "Rise", minutes: 100, plain: true).question == "Start a 1 hour 40 minute timer?")
        #expect(TimerOffer(label: "Pasta", minutes: 9, plain: false, ingredient: "pasta").question == "Start a 9-minute timer?")
        #expect(TimerOffer(label: "Stew", minutes: 90, plain: true).question == "Start a 90-minute timer?")
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
        // "serves" may be left out, so only the typo is reported, not a missing field.
        #expect(!lines.contains { $0.contains("missing \"serves\"") }, "\(lines)")
        #expect(lines.allSatisfy { $0.contains(".json: ") })
    }
}
