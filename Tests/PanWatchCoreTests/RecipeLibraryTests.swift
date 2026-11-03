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
}
