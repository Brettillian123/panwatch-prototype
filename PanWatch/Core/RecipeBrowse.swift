import Foundation

/// One ingredient split for a two-column list: "Pasta" and "1 pound".
struct IngredientLine: Equatable, Sendable {
    let name: String
    /// Empty when the line names no amount.
    let amount: String

    /// Splits a recipe's ingredient line. "4 cloves of garlic, minced" is "Garlic, minced" and
    /// "4 cloves"; "4 eggs" is "Eggs" and "4"; a line with neither is all name.
    init(_ line: String) {
        let text = line.trimmingCharacters(in: .whitespaces)
        if let range = text.range(of: " of ") {
            self.init(name: String(text[range.upperBound...]), amount: String(text[..<range.lowerBound]))
        } else if let space = text.firstIndex(of: " "), text[..<space].allSatisfy({ $0.isNumber || $0 == "/" }) {
            self.init(name: String(text[text.index(after: space)...]), amount: String(text[..<space]))
        } else {
            self.init(name: text, amount: "")
        }
    }

    init(name: String, amount: String) {
        self.name = name.prefix(1).uppercased() + name.dropFirst()
        self.amount = amount
    }
}

extension Recipe {
    /// Recipes this long or shorter go in Home's "Quick ones" row.
    static let quickMinutes = 20

    /// The title in sentence case, as the screens show it: "Hard-boiled eggs".
    var displayTitle: String {
        title.prefix(1).uppercased() + title.dropFirst().lowercased()
    }

    /// "20 min · Serves 4".
    var summary: String { "\(totalMinutes) min · Serves \(serves)" }

    var isQuick: Bool { totalMinutes <= Recipe.quickMinutes }

    var ingredientLines: [IngredientLine] { ingredients.map(IngredientLine.init) }

    /// The recipes whose name or an ingredient holds every word of `query`, in menu order.
    /// An empty query matches them all.
    static func matching(_ query: String, in recipes: [Recipe] = Recipe.all) -> [Recipe] {
        let words = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return recipes }
        return recipes.filter { recipe in
            let haystack = ([recipe.title] + recipe.ingredients).joined(separator: " ").lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }
}
