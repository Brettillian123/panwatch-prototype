import Foundation

/// Which recipes the cook has started and finished, and when, kept in `UserDefaults`
/// beside the per-cook `CookStats`. Home's suggestion comes from it.
struct CookHistory: Equatable, Codable, Sendable {
    static let key = "cookHistory.v1"

    /// Recipe id to the last time it was started.
    private(set) var started: [String: Date] = [:]
    /// Recipe id to the last time its last step was reached.
    private(set) var finished: [String: Date] = [:]

    mutating func noteStarted(_ recipe: Recipe, at date: Date = Date()) { started[recipe.id] = date }
    mutating func noteFinished(_ recipe: Recipe, at date: Date = Date()) { finished[recipe.id] = date }

    func hasCooked(_ recipe: some BookItem) -> Bool { started[recipe.id] != nil || finished[recipe.id] != nil }

    /// When the recipe was last cooked, started or finished.
    func lastCooked(_ recipe: some BookItem) -> Date? {
        [started[recipe.id], finished[recipe.id]].compactMap { $0 }.max()
    }

    /// The first recipe in book order never cooked; once all have been, the one cooked
    /// longest ago. Nil only for an empty book.
    func suggestion<Item: BookItem>(from recipes: [Item]) -> Item? {
        if let fresh = recipes.first(where: { !hasCooked($0) }) { return fresh }
        return recipes.min { (lastCooked($0) ?? .distantPast) < (lastCooked($1) ?? .distantPast) }
    }

    static func load(from defaults: UserDefaults = .standard) -> CookHistory {
        guard let data = defaults.data(forKey: key),
              let history = try? JSONDecoder().decode(CookHistory.self, from: data) else { return CookHistory() }
        return history
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: CookHistory.key) }
    }
}
