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
        #expect(Recipe.all.first?.title == "Garlic Butter Pasta")
    }

    @Test func sixRecipesForThePreview() {
        #expect(Recipe.all.count == 6)
    }

    @Test func everyRecipeListsItsIngredients() {
        for recipe in Recipe.all {
            #expect(recipe.ingredients.count >= 2, "\(recipe.title)")
        }
    }

    @Test func everyRecipeHasOneTimedAdditionTheCameraWatches() {
        for recipe in Recipe.all {
            let watched = recipe.steps.filter { $0.watch != nil }
            #expect(!watched.isEmpty, "\(recipe.title)")
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
                #expect(step.instruction.count <= 70, "\(recipe.title) step \(step.id)")
            }
        }
    }

    @Test func trimmedStepsKeepEveryNumberFromTheSpokenText() {
        func numbers(_ text: String) -> [String] {
            text.split(whereSeparator: { !$0.isNumber }).map(String.init)
        }
        for recipe in Recipe.all {
            for step in recipe.steps {
                guard let spoken = step.spoken else { continue }
                let shown = Set(numbers(step.instruction))
                for number in numbers(spoken) {
                    #expect(shown.contains(number), "\(recipe.title) step \(step.id): \(number)")
                }
            }
        }
    }

    @Test func everyRecipePassesTheChecks() {
        for recipe in Recipe.all {
            #expect(recipe.problems().isEmpty, "\(recipe.title)")
        }
    }
}
