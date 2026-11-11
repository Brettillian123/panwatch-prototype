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

    var ingredientLines: [IngredientLine] { items.map { IngredientLine(name: $0.name, amount: $0.amount) } }

    /// The recipes whose name, an ingredient or the category holds every word of `query`:
    /// those matched by name first, then the rest, each in book order. A word matches part
    /// of a word ("gar" finds garlic), a plural ("egg" finds eggs), or a word one letter off
    /// ("brocoli"; two off for long words). An empty query matches them all.
    static func matching(_ query: String, in recipes: [Recipe] = Recipe.all) -> [Recipe] {
        let words = SearchWords.words(in: query)
        guard !words.isEmpty else { return recipes }
        var byName: [Recipe] = []
        var byOther: [Recipe] = []
        for recipe in recipes {
            let name = SearchWords.words(in: recipe.title)
            let other = SearchWords.words(in: (recipe.items.map(\.name) + [recipe.category.title]).joined(separator: " "))
            guard words.allSatisfy({ SearchWords.matches($0, any: name + other) }) else { continue }
            if words.allSatisfy({ SearchWords.matches($0, any: name) }) { byName.append(recipe) } else { byOther.append(recipe) }
        }
        return byName + byOther
    }

    /// The recipes a list filter keeps, in book order.
    static func filtered(_ filter: RecipeFilter, in recipes: [Recipe] = Recipe.all) -> [Recipe] {
        switch filter {
        case .all: recipes
        case .quick: recipes.filter(\.isQuick)
        case .stovetop: recipes.filter(\.method.cameraCanHelp)
        case .category(let category): recipes.filter { $0.category == category }
        }
    }
}

/// What the recipe list shows: everything, the quick ones, the stovetop ones (where the
/// camera can help), or one category.
enum RecipeFilter: Hashable, Sendable {
    case all, quick, stovetop
    case category(RecipeCategory)

    /// The chip's words, in plain words.
    var title: String {
        switch self {
        case .all: "All"
        case .quick: "Under 20 min"
        case .stovetop: "Stovetop"
        case .category(let category): category.title
        }
    }

    /// The chips in the order the list shows them: the three, then every category.
    static var chips: [RecipeFilter] { [.all, .quick, .stovetop] + RecipeCategory.allCases.map { .category($0) } }
}

/// Forgiving word matching for search.
enum SearchWords {
    static func words(in text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// "Eggs" and "egg", "tomatoes" and "tomato" are the same word.
    static func stem(_ word: String) -> String {
        if word.count > 4 && word.hasSuffix("oes") { return String(word.dropLast(2)) }
        if word.count > 3 && word.hasSuffix("s") && !word.hasSuffix("ss") { return String(word.dropLast()) }
        return word
    }

    static func matches(_ said: String, any words: [String]) -> Bool {
        words.contains { matches(said, $0) }
    }

    static func matches(_ said: String, _ word: String) -> Bool {
        if word.hasPrefix(said) || stem(word) == stem(said) { return true }
        let allowed = said.count >= 8 ? 2 : said.count >= 5 ? 1 : 0
        guard allowed > 0, abs(said.count - word.count) <= allowed else { return false }
        return distance(stem(said), stem(word), atMost: allowed) <= allowed
    }

    /// The edit distance between two words, stopping early once it passes `atMost`.
    static func distance(_ a: String, _ b: String, atMost limit: Int) -> Int {
        let a = Array(a), b = Array(b)
        var previous = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var current = [i] + Array(repeating: 0, count: b.count)
            var best = i
            for j in 1...max(b.count, 1) where !b.isEmpty {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                best = min(best, current[j])
            }
            if best > limit { return best }
            previous = current
        }
        return a.isEmpty ? b.count : previous[b.count]
    }
}
