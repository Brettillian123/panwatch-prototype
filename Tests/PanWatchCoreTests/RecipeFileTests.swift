import Foundation
import Testing
@testable import PanWatchCore

/// The recipe as it was written in Swift before the recipes became files, kept fixed so
/// the file format stays honest: the file must load to exactly this.
private struct SwiftRecipe {
    let title: String
    let steps: [RecipeStep]
    let ingredients: [String]
    let totalMinutes: Int
    let serves: Int
}

private let swiftGarlicButterPasta = SwiftRecipe(
    title: "Garlic Butter Pasta",
    steps: [
        RecipeStep(id: 1, instruction: "Bring 4 quarts of water and 1 tablespoon of salt to a boil.", watch: nil),
        RecipeStep(
            id: 2,
            instruction: "Add 1 pound of pasta to the boiling water.",
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

@Suite("Recipe files")
struct RecipeFileTests {
    /// All six were compared field by field when they became files (Nov 10); one stays
    /// as fixed expected values so the format and the loader can't drift.
    private static let swiftRecipes = [swiftGarlicButterPasta]

    @Test(arguments: swiftRecipes.indices)
    func eachFileLoadsToTheRecipeAsItWasWrittenInSwift(_ index: Int) throws {
        let old = Self.swiftRecipes[index]
        let loaded = try #require(Recipe.all.first { $0.title == old.title }, "\(old.title)")
        #expect(loaded.steps.count == old.steps.count, "\(old.title)")
        for (new, before) in zip(loaded.steps, old.steps) {
            #expect(new.id == before.id)
            #expect(new.instruction == before.instruction)
            #expect(new.spoken == before.spoken)
            #expect(new.watch == before.watch, "\(old.title) step \(before.id)")
            #expect(new.cue == before.cue, "\(old.title) step \(before.id)")
            #expect(new.timer == nil)
        }
        #expect(loaded.ingredients == old.ingredients)
        #expect(loaded.totalMinutes == old.totalMinutes)
        #expect(loaded.serves == old.serves)
        #expect(loaded.id == Recipe.slug(of: old.title))
        #expect(loaded.source.isOwn)
    }

    @Test func theBookLoadsInTheTestsFromTheResourceFolder() throws {
        let folder = try #require(RecipeBook.packedFolder())
        #expect(folder.lastPathComponent == "RecipeBook")
        let loaded = RecipeBook.load(from: BookPaths.sources)
        #expect(loaded.problems.isEmpty, "\(loaded.problems.map(\.line))")
        #expect(loaded.recipes.count == Recipe.all.count)
        #expect(Recipe.all.count >= 6)
    }

    /// The app's bundle has the packed files at its top, beside other resources: the same
    /// loader finds them there.
    @Test func theBookLoadsFromAFlatFolderLikeTheAppBundle() throws {
        let source = try #require(RecipeBook.packedFolder())
        let flat = FileManager.default.temporaryDirectory.appendingPathComponent("flat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: flat, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: flat) }
        for name in try FileManager.default.contentsOfDirectory(atPath: source.path) {
            try FileManager.default.copyItem(at: source.appendingPathComponent(name), to: flat.appendingPathComponent(name))
        }
        try Data(#"{"voices": ["a", "b"]}"#.utf8).write(to: flat.appendingPathComponent("voices.json"))
        let loaded = RecipeBook.inBookOrder((0..<RecipeBook.shardCount).flatMap { Array(RecipeBook.shard($0, in: flat).values) })
        #expect(loaded == Recipe.all)
        for recipe in Recipe.all { #expect(RecipeBook.recipe(id: recipe.id, in: flat) == recipe) }
    }

    @Test func theBookIsInCategoryThenTitleOrder() {
        let keys = Recipe.all.map { ($0.category.index, $0.title.lowercased()) }
        #expect(zip(keys, keys.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(Recipe.all.prefix(6).map(\.id) == [
            "garlic-butter-pasta", "rice", "hard-boiled-eggs", "oatmeal", "steamed-broccoli", "pan-seared-chicken",
        ])
    }

    @Test func ingredientsReadAloudAsBefore() {
        #expect(Ingredient(name: "pasta", amount: "1 pound").spoken == "1 pound of pasta")
        #expect(Ingredient(name: "eggs", amount: "4").spoken == "4 eggs")
        #expect(Ingredient(name: "salt", amount: "to taste").spoken == "salt, to taste")
        #expect(Ingredient(name: "ice water", amount: "a bowl").spoken == "a bowl of ice water")
        #expect(Ingredient(name: "onion", amount: "1 large").spoken == "1 large onion")
        #expect(Ingredient(name: "milk", amount: "1 1/2 cups").spoken == "1 1/2 cups of milk")
    }

    @Test func aFileWithAnUnknownCategoryOrMethodSaysWhich() {
        let base = #"{"id":"x","title":"X","category":"CATEGORY","method":"METHOD","source":{"name":"Sous Vision"},"serves":2,"totalMinutes":10,"ingredients":[],"steps":[]}"#
        let badCategory = base.replacingOccurrences(of: "CATEGORY", with: "Desserts").replacingOccurrences(of: "METHOD", with: "pot")
        let badMethod = base.replacingOccurrences(of: "CATEGORY", with: "Soups").replacingOccurrences(of: "METHOD", with: "grill")
        guard case .failure(let category) = RecipeBook.decode(Data(badCategory.utf8)),
              case .failure(let method) = RecipeBook.decode(Data(badMethod.utf8)) else {
            Issue.record("both should fail"); return
        }
        #expect(category.text.contains("unknown category \"Desserts\""))
        #expect(method.text.contains("unknown method \"grill\""))
        guard case .failure(let missing) = RecipeBook.decode(Data(#"{"title":"X"}"#.utf8)) else {
            Issue.record("should fail"); return
        }
        #expect(missing.text.hasPrefix("missing"))
    }
}
