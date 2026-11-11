import Testing
@testable import PanWatchCore

@Suite("Recipe library")
struct RecipeLibraryTests {
    @Test func libraryIsNotEmpty() {
        #expect(!Recipe.all.isEmpty)
    }

    @Test func everyTitleIsUnique() {
        let titles = Recipe.all.map(\.title)
        #expect(Set(titles).count == titles.count)
    }

    @Test func firstRecipeIsGarlicButterPasta() {
        #expect(DemoBook.recipes.first?.title == "Garlic Butter Pasta")
        #expect(DemoBook.recipes.count == 6, "the six demo dishes are all in the shipped book")
    }

    @Test func sixRecipesForThePreview() {
        #expect(Recipe.all.count >= 6)
    }

    @Test func everyRecipeListsItsIngredients() {
        for recipe in Recipe.all {
            #expect(recipe.ingredients.count >= 2, "\(recipe.title)")
        }
    }

    /// The six demo dishes each have a step the camera watches; in the whole book a watch is
    /// only on pot and pan recipes and always offers a timer.
    @Test func everyRecipeHasOneTimedAdditionTheCameraWatches() {
        for recipe in DemoBook.recipes {
            #expect(recipe.steps.contains { $0.watch != nil }, "\(recipe.title)")
        }
        for recipe in Recipe.all {
            let watched = recipe.steps.filter { $0.watch != nil }
            #expect(watched.isEmpty || recipe.method.cameraCanHelp, "\(recipe.title)")
            #expect(watched.allSatisfy { ($0.watch?.timerMinutes ?? 0) > 0 }, "\(recipe.title)")
        }
    }

    @Test func theChickenIsCheckedWithAThermometer() {
        let flip = Recipe.panSearedChicken.steps.first { $0.cue?.timerLabel == "Chicken" }
        #expect(flip?.instruction.contains("165") == true)
        #expect(flip?.instruction.contains("thermometer") == true)
    }

    @Test func theIceBathIsReadyBeforeTheEggs() {
        let cues = Recipe.hardBoiledEggs.steps.compactMap(\.cue)
        #expect(cues.map(\.secondsLeft) == [120, 0])
    }

    @Test func everyInstructionFitsLargeType() {
        for recipe in Recipe.all {
            for step in recipe.steps {
                #expect(step.instruction.count <= RecipeRules.instructionLimit, "\(recipe.title) step \(step.id)")
            }
        }
    }

    /// The screen and the spoken text never disagree on a number: every number on screen is
    /// said, and the spoken text adds only amounts and a range's upper end, never a time or a
    /// temperature the screen lacks (`RecipeRules.numberProblems`, also in the checker).
    @Test func trimmedStepsKeepEveryNumberFromTheSpokenText() {
        var breaking: Set<String> = []
        for recipe in Recipe.all {
            for step in recipe.steps {
                guard let spoken = step.spoken else { continue }
                let earlier = recipe.steps.prefix { $0.id < step.id }.map(\.instruction)
                let problems = RecipeRules.numberProblems(
                    shown: step.instruction, spoken: spoken, earlier: earlier,
                    amounts: recipe.items.map { $0.amount + " " + $0.name },
                    timerMinutes: [step.watch?.timerMinutes, step.timer?.minutes].compactMap { $0 })
                if !problems.isEmpty { breaking.insert(recipe.id) }
            }
        }
        #expect(breaking.sorted() == [])
        for recipe in DemoBook.recipes { #expect(!breaking.contains(recipe.id), "\(recipe.title)") }
    }

    @Test func theNumberRuleNamesWhatDisagrees() {
        #expect(RecipeRules.numberProblems(shown: "Cook 3 minutes.", spoken: "Cook 3 to 4 minutes, stirring.").isEmpty)
        #expect(RecipeRules.numberProblems(shown: "Add the pepper.", spoken: "Add 1/4 teaspoon of pepper.", amounts: ["1/4 teaspoon pepper"]).isEmpty)
        #expect(RecipeRules.numberProblems(shown: "Cook 5 minutes.", spoken: "Cook five minutes.").isEmpty)
        #expect(RecipeRules.numberProblems(shown: "Add the garlic.", spoken: "Add 2 minced garlic cloves.").isEmpty)
        let time = RecipeRules.numberProblems(shown: "Add the onion.", spoken: "Add the onion and cook 8 minutes.")
        #expect(time.count == 1 && time[0].contains("8 minutes"))
        // A temperature to look for may be only in the spoken text; a setting may not.
        #expect(RecipeRules.numberProblems(shown: "Flip the chicken.", spoken: "Flip it, until a thermometer reads 165 °F.").isEmpty)
        let heat = RecipeRules.numberProblems(shown: "Bake the bread.", spoken: "Bake the bread at 375 °F.")
        #expect(heat.count == 1 && heat[0].contains("375 °F"))
        let range = RecipeRules.numberProblems(shown: "Cook the pecans.", spoken: "Cook the pecans 2 to 3 minutes.")
        #expect(range.count == 1 && range[0].contains("2 minutes"))
        let dropped = RecipeRules.numberProblems(shown: "Add 4 cloves of garlic.", spoken: "Add the garlic.")
        #expect(dropped == ["The screen says 4 cloves but the spoken text leaves it out; say every number the screen shows."])
        let changed = RecipeRules.numberProblems(shown: "Add 2 cups of broth.", spoken: "Add 3 cups of broth.")
        #expect(changed.first == "The screen says 2 cups but the spoken text says 3 cups; make them match.")
        // Same value in other words.
        #expect(RecipeRules.numberProblems(shown: "Add 1/2 cup of milk.", spoken: "Add half a cup of milk.").isEmpty)
        #expect(RecipeRules.numberProblems(shown: "Add 1 1/2 cups of rice.", spoken: "Add one and a half cups of rice.").isEmpty)
        // A size to look for, an amount shown earlier, the step's own timer.
        #expect(RecipeRules.numberProblems(shown: "Roll out the dough.", spoken: "Roll it into a 12-inch circle.").isEmpty)
        #expect(RecipeRules.numberProblems(shown: "Add the rest of the sugar.", spoken: "Add the last 2 tablespoons of sugar.",
                                           earlier: ["Add 2 tablespoons of sugar."]).isEmpty)
        #expect(RecipeRules.numberProblems(shown: "Add the peas.", spoken: "Add the peas and simmer 5 minutes.", timerMinutes: [5]).isEmpty)
        #expect(!RecipeRules.numberProblems(shown: "Add the rest of the sugar.", spoken: "Add 3 cups of sugar.").isEmpty)
    }

    @Test func everyRecipePassesTheChecks() {
        for recipe in Recipe.all {
            #expect(recipe.problems().isEmpty, "\(recipe.title)")
        }
    }
}
