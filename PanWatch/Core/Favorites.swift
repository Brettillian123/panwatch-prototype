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
    static func load(from defaults: UserDefaults = .standard, recipes: [some BookItem]) -> Favorites {
        load(from: defaults, titles: recipes.map(\.title))
    }

    static func load(from defaults: UserDefaults = .standard, titles: [String] = RecipeIndex.bundled.titles) -> Favorites {
        let saved = defaults.stringArray(forKey: key) ?? []
        let known = Set(titles)
        return Favorites(titles: saved.filter { known.contains($0) })
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(titles, forKey: Favorites.key)
    }

    func contains(_ recipe: some BookItem) -> Bool { titles.contains(recipe.title) }

    /// Hearts the recipe, or takes the heart away.
    mutating func toggle(_ recipe: some BookItem) {
        if let index = titles.firstIndex(of: recipe.title) {
            titles.remove(at: index)
        } else {
            titles.append(recipe.title)
        }
    }

    /// The hearted recipes in menu order.
    func contains(_ recipe: Recipe) -> Bool { titles.contains(recipe.title) }
    mutating func toggle(_ recipe: Recipe) { toggle(RecipeEntry(recipe, hasPhoto: false)) }

    /// The hearted dishes from the book's index, in book order.
    func recipes() -> [RecipeEntry] { recipes(in: RecipeIndex.bundled.entries) }

    func recipes<Item: BookItem>(in all: [Item]) -> [Item] {
        all.filter { contains($0) }
    }
}
