import Foundation

/// The recipes the cook has hearted, by title, kept in `UserDefaults`.
struct Favorites: Equatable, Sendable {
    static let key = "favorites.v1"

    /// Titles in the order they were hearted.
    private(set) var titles: [String] = []

    init(titles: [String] = []) {
        self.titles = titles
    }

    /// The saved favorites, keeping only titles that are still recipes.
    static func load(from defaults: UserDefaults = .standard, recipes: [Recipe] = Recipe.all) -> Favorites {
        let saved = defaults.stringArray(forKey: key) ?? []
        let known = Set(recipes.map(\.title))
        return Favorites(titles: saved.filter { known.contains($0) })
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(titles, forKey: Favorites.key)
    }

    func contains(_ recipe: Recipe) -> Bool { titles.contains(recipe.title) }

    /// Hearts the recipe, or takes the heart away.
    mutating func toggle(_ recipe: Recipe) {
        if let index = titles.firstIndex(of: recipe.title) {
            titles.remove(at: index)
        } else {
            titles.append(recipe.title)
        }
    }

    /// The hearted recipes in menu order.
    func recipes(in all: [Recipe] = Recipe.all) -> [Recipe] {
        all.filter(contains)
    }
}
