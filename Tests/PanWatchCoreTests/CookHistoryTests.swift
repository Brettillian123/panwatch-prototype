import Foundation
import Testing
@testable import PanWatchCore

@Suite("Cook history")
struct CookHistoryTests {
    private let book = Array(Recipe.all.prefix(3))

    @Test func suggestsTheFirstDishNotCookedYet() {
        var history = CookHistory()
        #expect(history.suggestion(from: book)?.id == book[0].id)
        history.noteStarted(book[0])
        #expect(history.suggestion(from: book)?.id == book[1].id)
    }

    @Test func onceAllAreCookedSuggestsTheOneCookedLongestAgo() {
        var history = CookHistory()
        let now = Date()
        history.noteStarted(book[0], at: now.addingTimeInterval(-100))
        history.noteStarted(book[1], at: now.addingTimeInterval(-300))
        history.noteFinished(book[1], at: now.addingTimeInterval(-10))
        history.noteStarted(book[2], at: now.addingTimeInterval(-200))
        #expect(history.suggestion(from: book)?.id == book[2].id)
    }

    @Test func savesAndLoads() throws {
        let defaults = try #require(UserDefaults(suiteName: "cook-history-\(UUID().uuidString)"))
        #expect(CookHistory.load(from: defaults) == CookHistory())
        var history = CookHistory()
        history.noteStarted(book[0])
        history.noteFinished(book[0])
        history.save(to: defaults)
        #expect(CookHistory.load(from: defaults) == history)
        #expect(CookHistory.load(from: defaults).hasCooked(book[0]))
    }

    @Test func sourcedRecipesAreCreditedOwnOnesAreNot() {
        // The demo dishes are the app's own: no notice.
        #expect(Credits.recipeNotices(DemoBook.index.entries).isEmpty)
        // Every outside source in the shipped book is credited once.
        let shipped = Set(RecipeIndex.bundled.entries.map(\.source)).subtracting([RecipeSource.own.name])
        #expect(Set(Credits.recipeNotices().map(\.title)) == shipped)
        var lentils = Recipe(title: "Lentil Soup", category: .soups, steps: [])
        lentils.source = RecipeSource(name: "Serious Eats", url: "https://www.seriouseats.com/lentil-soup")
        let entries = [RecipeEntry(lentils, hasPhoto: false), RecipeEntry(Recipe.rice, hasPhoto: false), RecipeEntry(lentils, hasPhoto: false)]
        let sources = [RecipeSourceCredit(name: "Serious Eats", credit: "Recipes adapted from Serious Eats.", url: "https://www.seriouseats.com")]
        let notices = Credits.recipeNotices(entries, sources: sources)
        #expect(notices.map(\.title) == ["Serious Eats"])
        #expect(notices.first?.text == "Recipes adapted from Serious Eats.\nhttps://www.seriouseats.com")
    }

    @Test func listFiltersKeepTheirRecipes() {
        #expect(Recipe.filtered(.all) == Recipe.all)
        let quick = Recipe.filtered(.quick).map(\.isQuick)
        #expect(!quick.isEmpty && !quick.contains(false))
        let stovetop = Recipe.filtered(.stovetop).map(\.method.cameraCanHelp)
        #expect(!stovetop.contains(false))
        #expect(Recipe.filtered(.category(.chicken), in: DemoBook.recipes).map(\.id) == ["pan-seared-chicken"])
        #expect(Recipe.filtered(.category(.chicken)).allSatisfy { $0.category == .chicken })
        #expect(RecipeFilter.chips.map(\.title).prefix(3) == ["All", "Under 20 min", "Stovetop"])
        #expect(RecipeFilter.chips.count == 3 + RecipeCategory.allCases.count)
        for chip in RecipeFilter.chips { #expect(PlainWords.bannedWords(in: chip.title).isEmpty) }
    }
}
