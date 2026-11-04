import Foundation

/// The cook in progress, saved whenever it changes, so closing the app or putting the
/// phone down never loses the recipe.
struct SavedCook: Codable, Equatable, Sendable {
    /// Recipes are saved by title, so a recipe renamed or removed since is not resumed.
    let recipeTitle: String
    let stepIndex: Int
    /// Watched steps whose ingredient already went in.
    let finishedSteps: Set<Int>
    let savedAt: Date

    /// How long a cook can be picked up again. Past this the app opens on the recipe menu.
    static let lifetime: TimeInterval = 6 * 60 * 60

    func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }

    /// Nil for missing or damaged data, never a crash.
    static func decode(_ data: Data) -> SavedCook? {
        try? JSONDecoder().decode(SavedCook.self, from: data)
    }

    /// The recipe to resume from `recipes`, or nil when the cook is older than `lifetime`,
    /// its recipe no longer exists, or the step it was on is gone.
    func recipe(in recipes: [Recipe], at now: Date) -> Recipe? {
        guard now.timeIntervalSince(savedAt) < Self.lifetime,
              let recipe = recipes.first(where: { $0.title == recipeTitle }),
              recipe.steps.indices.contains(stepIndex) else { return nil }
        return recipe
    }
}
