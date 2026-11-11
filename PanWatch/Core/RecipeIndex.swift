import Foundation

/// What the screens and voice need to know about a dish without reading its file: a full
/// `Recipe` and an index `RecipeEntry` both are one.
protocol BookItem {
    var id: String { get }
    var title: String { get }
    var category: RecipeCategory { get }
    var method: CookMethod { get }
    var totalMinutes: Int { get }
    var serves: Int? { get }
}

extension BookItem {
    /// Recipes this long or shorter go in Home's "Quick ones" row.
    static var quickMinutes: Int { 20 }

    /// The title in sentence case, as the screens show it: "Hard-boiled eggs".
    var displayTitle: String {
        title.prefix(1).uppercased() + title.dropFirst().lowercased()
    }

    /// "20 min · Serves 4", or "8 hr" alone when the source gives no serving count.
    var summary: String { serves.map { "\(timeText) · Serves \($0)" } ?? timeText }

    /// The total time as the screens show it: "25 min", "1 hr 30 min", "8 hr".
    var timeText: String { Recipe.timeText(minutes: totalMinutes) }

    /// For the voice and VoiceOver: "25 minutes", "1 hour 30 minutes", "8 hours".
    var spokenTime: String { Recipe.spokenTime(minutes: totalMinutes) }

    var isQuick: Bool { totalMinutes <= Recipe.quickMinutes }

    /// The name of the dish's photo in the asset catalog, "dish-<slug>".
    var photoName: String { "dish-" + id }
}

/// One dish in the book's index, `recipebook-index.json`: enough for shelves, lists, search,
/// voice and credits. The full recipe is read from its shard when it is opened.
struct RecipeEntry: BookItem, Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let category: RecipeCategory
    let method: CookMethod
    let totalMinutes: Int
    let serves: Int?
    /// Ingredient names as written, "garlic, minced".
    let ingredients: [String]
    /// The source's name, "Sous Vision" for the app's own.
    let source: String
    /// The program or author the source credits, for the About credits; nil when none.
    var credit: String? = nil
    /// The app has the photo `dish-<id>`; without it the screens draw the plain tile.
    let hasPhoto: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, category, method, totalMinutes = "minutes", serves, ingredients, source, credit, hasPhoto = "photo"
    }
}

extension RecipeEntry {
    init(_ recipe: Recipe, hasPhoto: Bool) {
        self.init(id: recipe.id, title: recipe.title, category: recipe.category, method: recipe.method,
                  totalMinutes: recipe.totalMinutes, serves: recipe.serves, ingredients: recipe.items.map(\.name),
                  source: recipe.source.name,
                  credit: recipe.source.credit.isEmpty ? nil : recipe.source.credit, hasPhoto: hasPhoto)
    }
}

/// The whole book as one small index, read once; search and filters run on it.
final class RecipeIndex: Sendable {
    /// In book order: by category, then by title.
    let entries: [RecipeEntry]
    /// Every title, in book order, for voice.
    let titles: [String]
    private let byID: [String: Int]
    private let byTitle: [String: Int]
    /// Search words per entry, stemmed once: the title's, then the ingredients' and category's.
    private let titleWords: [[SearchKey]]
    private let otherWords: [[SearchKey]]

    init(entries: [RecipeEntry]) {
        let sorted = entries.sorted {
            ($0.category.index, $0.title.lowercased()) < ($1.category.index, $1.title.lowercased())
        }
        self.entries = sorted
        titles = sorted.map(\.title)
        var byID: [String: Int] = [:]
        var byTitle: [String: Int] = [:]
        for (place, entry) in sorted.enumerated() {
            byID[entry.id] = byID[entry.id] ?? place
            byTitle[entry.title.lowercased()] = byTitle[entry.title.lowercased()] ?? place
        }
        self.byID = byID
        self.byTitle = byTitle
        titleWords = sorted.map { SearchWords.words(in: $0.title).map(SearchKey.init) }
        otherWords = sorted.map { SearchWords.words(in: ($0.ingredients + [$0.category.title]).joined(separator: " ")).map(SearchKey.init) }
    }

    func entry(id: String) -> RecipeEntry? { byID[id].map { entries[$0] } }
    func entry(titled title: String) -> RecipeEntry? { byTitle[title.lowercased()].map { entries[$0] } }
    func position(of id: String) -> Int? { byID[id] }
    func entries(titled titles: [String]) -> [RecipeEntry] { titles.compactMap { entry(titled: $0) } }

    /// The entries a list filter keeps, in book order.
    func filtered(_ filter: RecipeFilter) -> [RecipeEntry] {
        switch filter {
        case .all: entries
        case .quick: entries.filter(\.isQuick)
        case .stovetop: entries.filter(\.method.cameraCanHelp)
        case .category(let category): entries.filter { $0.category == category }
        }
    }

    /// The entries whose name, an ingredient or the category holds every word of `query`,
    /// ranked: names that start with it, then names that hold it, then the rest; book order
    /// within each. Parts of words, plurals and one-letter typos match (`SearchWords`). An
    /// empty query keeps them all. `within` limits it to a filter's entries.
    func search(_ query: String, within filter: RecipeFilter = .all) -> [RecipeEntry] {
        let words = SearchWords.words(in: query).map(SearchKey.init)
        guard !words.isEmpty else { return filtered(filter) }
        var startsWith: [RecipeEntry] = [], inName: [RecipeEntry] = [], other: [RecipeEntry] = []
        for (place, entry) in entries.enumerated() where filter.keeps(entry) {
            let name = titleWords[place]
            if words.allSatisfy({ $0.matches(any: name) }) {
                if let first = name.first, words[0].matches(first) {
                    startsWith.append(entry)
                } else {
                    inName.append(entry)
                }
            } else if words.allSatisfy({ $0.matches(any: name) || $0.matches(any: otherWords[place]) }) {
                other.append(entry)
            }
        }
        return startsWith + inName + other
    }

    // MARK: The bundled index

    /// The index that shipped with this build, read on first use. The app starts reading
    /// it off the main thread at launch (`preload`); nothing parses the recipes themselves.
    static let bundled: RecipeIndex = {
        guard let folder = RecipeBook.packedFolder(),
              let data = FileManager.default.contents(atPath: folder.appendingPathComponent(RecipeBook.packedIndexFile).path),
              let index = try? decode(data) else { return RecipeIndex(entries: []) }
        return index
    }()

    /// Reads the bundled index in the background so the first screen finds it ready.
    static func preload() {
        Task.detached(priority: .userInitiated) { _ = RecipeIndex.bundled }
    }

    // MARK: The file

    private struct File: Codable {
        let version: Int
        let recipes: [RecipeEntry]
    }

    static func decode(_ data: Data) throws -> RecipeIndex {
        RecipeIndex(entries: try JSONDecoder().decode(File.self, from: data).recipes)
    }

    /// The index file's text: one entry per line, keys sorted, so a new batch of recipes
    /// shows in a diff as new lines.
    static func encode(_ entries: [RecipeEntry]) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let lines = RecipeIndex(entries: entries).entries.compactMap { entry in
            (try? encoder.encode(entry)).flatMap { String(data: $0, encoding: .utf8) }
        }
        return Data(("{\"version\":1,\"recipes\":[\n" + lines.joined(separator: ",\n") + "\n]}\n").utf8)
    }

    /// The index for the recipe files in `folder`. A recipe has a photo when the asset
    /// catalog `assets` (beside `Core`) holds `dish-<id>.imageset`.
    static func build(folder: URL, assets: URL?) -> [RecipeEntry] {
        let photos = Set(((assets.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) }) ?? [])
            .filter { $0.hasSuffix(".imageset") }.map { String($0.dropLast(".imageset".count)) })
        return RecipeBook.load(from: folder).recipes.map { RecipeEntry($0, hasPhoto: photos.contains($0.photoName)) }
    }
}

extension RecipeFilter {
    func keeps(_ item: some BookItem) -> Bool {
        switch self {
        case .all: true
        case .quick: item.isQuick
        case .stovetop: item.method.cameraCanHelp
        case .category(let category): item.category == category
        }
    }
}

/// One outside source of recipes and its credit, from `Recipes/sources.json`, for Profile >
/// Advanced > About.
struct RecipeSourceCredit: Codable, Equatable, Sendable {
    let name: String
    /// The line the source asks for, or a plain "Recipes adapted from Serious Eats."
    let credit: String
    let url: String
}

extension RecipeBook {
    /// The credits in `folder/sources.json`; empty when there is none.
    static func sources(in folder: URL) -> [RecipeSourceCredit] {
        guard let data = FileManager.default.contents(atPath: folder.appendingPathComponent(sourcesFile).path) else { return [] }
        return (try? JSONDecoder().decode([RecipeSourceCredit].self, from: data)) ?? []
    }
}

/// A search word made ready once, as bytes with its stem, so matching a query against a
/// thousand titles is byte compares: the same rules as `SearchWords.matches`.
struct SearchKey: Sendable {
    let bytes: [UInt8]
    let stem: [UInt8]

    init(_ word: String) {
        bytes = Array(word.utf8)
        stem = Array(SearchWords.stem(word).utf8)
    }

    func matches(any words: [SearchKey]) -> Bool { words.contains { matches($0) } }

    /// `self` is what was typed or said; `word` is in the book.
    func matches(_ word: SearchKey) -> Bool {
        if word.bytes.count >= bytes.count, word.bytes.starts(with: bytes) { return true }
        if stem == word.stem { return true }
        let allowed = bytes.count >= 8 ? 2 : bytes.count >= 5 ? 1 : 0
        guard allowed > 0, abs(bytes.count - word.bytes.count) <= allowed else { return false }
        return SearchKey.distance(stem, word.stem, atMost: allowed) <= allowed
    }

    /// Edit distance on bytes, stopping once it passes `limit`.
    static func distance(_ a: [UInt8], _ b: [UInt8], atMost limit: Int) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        if abs(a.count - b.count) > limit { return limit + 1 }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            var best = i
            for j in 1...b.count {
                current[j] = Swift.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                best = Swift.min(best, current[j])
            }
            if best > limit { return best }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
