import Foundation
import Testing
@testable import PanWatchCore

@Suite("Recipe browsing")
struct RecipeBrowseTests {
    @Test func everyRecipeHasTimeAndServings() {
        for recipe in Recipe.all {
            #expect(recipe.totalMinutes > 0, "\(recipe.title)")
            // A serving count is optional (the source may not say); when present it's real.
            #expect(recipe.serves.map { $0 > 0 } ?? true, "\(recipe.title)")
        }
    }

    /// The total covers every timer the recipe's steps offer.
    @Test func totalTimeCoversTheTimers() {
        for recipe in Recipe.all {
            let timed = recipe.steps.compactMap(\.watch).map(\.timerMinutes).reduce(0, +)
            #expect(recipe.totalMinutes > timed, "\(recipe.title)")
        }
    }

    @Test func summaryReads() {
        #expect(Recipe.garlicButterPasta.summary == "20 min · Serves 4")
    }

    @Test func quickOnesAreTwentyMinutesOrLess() {
        let quick = Recipe.all.filter(\.isQuick).map(\.title)
        #expect(quick.contains(Recipe.garlicButterPasta.title))
        #expect(quick.contains(Recipe.oatmeal.title))
        #expect(!quick.contains(Recipe.rice.title))
    }

    @Test func displayTitleIsSentenceCase() {
        #expect(Recipe.garlicButterPasta.displayTitle == "Garlic butter pasta")
        #expect(Recipe.hardBoiledEggs.displayTitle == "Hard-boiled eggs")
    }

    @Test func ingredientLinesSplitNameAndAmount() {
        #expect(IngredientLine("1 pound of pasta") == IngredientLine(name: "Pasta", amount: "1 pound"))
        #expect(IngredientLine("4 cloves of garlic, minced") == IngredientLine(name: "Garlic, minced", amount: "4 cloves"))
        #expect(IngredientLine("4 eggs") == IngredientLine(name: "Eggs", amount: "4"))
        #expect(IngredientLine("a pinch of salt") == IngredientLine(name: "Salt", amount: "a pinch"))
        #expect(IngredientLine("salt") == IngredientLine(name: "Salt", amount: ""))
        for recipe in Recipe.all {
            #expect(recipe.ingredientLines.count == recipe.ingredients.count)
            #expect(recipe.ingredientLines.allSatisfy { !$0.name.isEmpty })
        }
    }

    @Test func searchMatchesNameOrIngredient() {
        let book = DemoBook.recipes
        #expect(Recipe.matching("").count == Recipe.all.count)
        #expect(Recipe.matching("  ", in: book).count == book.count)
        // By name first, then by category: rice is in "Pasta and grains".
        #expect(Recipe.matching("PASTA", in: book).map(\.title) == [Recipe.garlicButterPasta.title, Recipe.rice.title])
        #expect(Recipe.matching("pasta grains", in: book).map(\.title) == [Recipe.garlicButterPasta.title, Recipe.rice.title])
        // Plurals and small typos are forgiven.
        // "Eggs" by name, then oatmeal by its category, "Eggs and breakfast".
        #expect(Recipe.matching("egg", in: book).map(\.title) == [Recipe.hardBoiledEggs.title, Recipe.oatmeal.title])
        #expect(Recipe.matching("brocoli", in: book).map(\.title) == [Recipe.steamedBroccoli.title])
        #expect(Recipe.matching("chiken", in: book).map(\.title) == [Recipe.panSearedChicken.title])
        #expect(Recipe.matching("breakfast", in: book).map(\.title) == [Recipe.hardBoiledEggs.title, Recipe.oatmeal.title])
        let butter = Recipe.matching("butter", in: book).map(\.title)
        #expect(butter == [Recipe.garlicButterPasta.title, Recipe.steamedBroccoli.title])
        #expect(Recipe.matching("brown sugar", in: book).map(\.title) == [Recipe.oatmeal.title])
        #expect(Recipe.matching("xyz", in: book).isEmpty)
    }
}

@Suite("Favorites")
struct FavoritesTests {
    private func freshDefaults() -> UserDefaults {
        let name = "favorites-test-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func toggleAddsAndRemoves() {
        var favorites = Favorites()
        #expect(!favorites.contains(.rice))
        favorites.toggle(.rice)
        #expect(favorites.contains(.rice))
        favorites.toggle(.rice)
        #expect(!favorites.contains(.rice))
    }

    @Test func recipesComeInMenuOrder() {
        var favorites = Favorites()
        favorites.toggle(.oatmeal)
        favorites.toggle(.garlicButterPasta)
        #expect(favorites.recipes().map(\.title) == [Recipe.garlicButterPasta.title, Recipe.oatmeal.title])
    }

    @Test func savesAndLoads() {
        let defaults = freshDefaults()
        #expect(Favorites.load(from: defaults).titles.isEmpty)
        var favorites = Favorites()
        favorites.toggle(.steamedBroccoli)
        favorites.save(to: defaults)
        #expect(Favorites.load(from: defaults).contains(.steamedBroccoli))
    }

    @Test func loadDropsUnknownTitles() {
        let defaults = freshDefaults()
        defaults.set(["Rice", "Toast"], forKey: Favorites.key)
        #expect(Favorites.load(from: defaults).titles == ["Rice"])
    }
}
