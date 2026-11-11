import Foundation

/// What the camera should watch for during a step, and the timer to offer when it sees it.
struct AdditionWatch: Equatable, Sendable {
    /// Spoken in the prompt: "Looks like the pasta went in."
    let ingredient: String
    let timerLabel: String
    let timerMinutes: Int
    /// Share of the pan that must change for this step, when it should be less than the
    /// usual setting. Zero means a hand visiting the pan and leaving is enough, for
    /// ingredients too small to see once they're in, like minced garlic.
    var minimumChange: Double? = nil
    /// For ingredients carried in the hand, like a handful of pasta: the hand opening over
    /// the pot counts too, even when the pot hides the food from a phone on the counter.
    var countsRelease = false
}

/// When a step should be announced on its own: once the named timer has this much time
/// left. It lets the parts of a dish finish together, like the garlic butter being ready
/// just as the pasta is done.
struct StepCue: Equatable, Sendable {
    let timerLabel: String
    /// Seconds left on that timer. Zero means when it finishes.
    let secondsLeft: Int
}

/// A timer a step names with no camera involved, like "Bake for 25 minutes": for oven and
/// no-heat recipes, where the camera never watches.
struct StepTimer: Equatable, Sendable {
    let label: String
    let minutes: Int
}

struct RecipeStep: Identifiable, Equatable, Sendable {
    let id: Int
    let instruction: String
    /// Nil for steps where the camera stays out of it.
    let watch: AdditionWatch?
    /// Nil for steps the cook moves to whenever they're ready.
    var cue: StepCue? = nil
    /// The full wording read aloud; the screen shows `instruction`. Nil when they match.
    var spoken: String? = nil
    /// A plain timer the step names, when no camera watches it.
    var timer: StepTimer? = nil
}

extension RecipeStep {
    /// What the app reads aloud: the full wording when the screen shows a shortened one.
    var spokenText: String { spoken ?? instruction }
}

/// The shelves of the recipe book, in the order Home shows them.
enum RecipeCategory: String, CaseIterable, Codable, Sendable {
    case pastaAndGrains = "Pasta and grains"
    case eggsAndBreakfast = "Eggs and breakfast"
    case vegetables = "Vegetables"
    case salads = "Salads"
    case chicken = "Chicken"
    case beefAndPork = "Beef and pork"
    case fish = "Fish"
    case soups = "Soups"
    case beansAndLentils = "Beans and lentils"
    case sandwichesAndWraps = "Sandwiches and wraps"
    case snacksAndSides = "Snacks and sides"
    case saucesAndDips = "Sauces and dips"
    case bakingAndDesserts = "Baking and desserts"
    case drinks = "Drinks"

    /// The words on screen: "Pasta and grains".
    var title: String { rawValue }

    /// The SF Symbol on a dish's plain tile while it has no photo.
    var symbol: String {
        switch self {
        case .pastaAndGrains: "fork.knife"
        case .eggsAndBreakfast: "sun.horizon"
        case .vegetables: "carrot"
        case .salads: "leaf"
        case .chicken: "bird"
        case .beefAndPork: "flame"
        case .fish: "fish"
        case .soups: "mug"
        case .beansAndLentils: "circle.hexagongrid"
        case .sandwichesAndWraps: "takeoutbag.and.cup.and.straw"
        case .snacksAndSides: "popcorn"
        case .saucesAndDips: "drop"
        case .bakingAndDesserts: "birthday.cake"
        case .drinks: "cup.and.saucer"
        }
    }

    /// Where it sits in `allCases`, for book order.
    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// The no-photo tile's color: neighbouring shelves alternate blush and sky, so a shelf of
    /// ten plain tiles reads as one deliberate run and the next shelf as a new one.
    var tileIsBlush: Bool { index.isMultiple(of: 2) }
}

/// The main way a dish is cooked.
enum CookMethod: String, CaseIterable, Codable, Sendable {
    /// In a pot on the stove: boiling, simmering, steaming.
    case pot
    /// In a pan on the stove: searing, frying, sautéing.
    case pan
    case oven
    /// Nothing is heated: salads, overnight oats.
    case noHeat

    /// The camera can watch what goes into a pot or pan on the stove.
    var cameraCanHelp: Bool { self == .pot || self == .pan }
}

/// Where a recipe comes from, for the credits on Profile.
struct RecipeSource: Equatable, Sendable {
    let name: String
    /// Empty for the app's own recipes.
    var url: String = ""
    /// The program or author the source credits for this recipe, shown under the source on
    /// the About credits; empty when it names none.
    var credit: String = ""

    static let own = RecipeSource(name: "Sous Vision")
    var isOwn: Bool { name == RecipeSource.own.name }
}

/// One thing to gather: "1 pound" of "pasta".
struct Ingredient: Equatable, Sendable {
    let name: String
    let amount: String

    /// The line read aloud: "1 pound of pasta", "4 eggs", "salt, to taste".
    var spoken: String {
        if amount.isEmpty { return name }
        if amount == "to taste" { return "\(name), to taste" }
        // "1 pound of pasta" when the amount ends in a unit; "4 eggs", "1 large onion" when not.
        let words = amount.lowercased().split(separator: " ").map(String.init)
        let unit = words.count >= 2 ? words.suffix(2).joined(separator: " ") : ""
        let endsInUnit = words.last.map(RecipeRules.isUnit) == true || RecipeRules.isUnit(unit)
        return endsInUnit ? "\(amount) of \(name)" : "\(amount) \(name)"
    }
}

struct Recipe: BookItem, Equatable, Sendable {
    /// The slug: lowercase words joined by hyphens, stable, and the file's name.
    let id: String
    let title: String
    var category: RecipeCategory
    var method: CookMethod
    var source: RecipeSource
    let steps: [RecipeStep]
    /// What to gather before starting.
    var items: [Ingredient]
    /// Start to plate, in minutes, counting the waits the steps name (boiling, timers, resting).
    var totalMinutes: Int
    /// How many people the amounts feed; nil when the source doesn't say.
    var serves: Int?

    init(id: String? = nil, title: String, category: RecipeCategory = .vegetables, method: CookMethod = .pot,
         source: RecipeSource = .own, steps: [RecipeStep], items: [Ingredient] = [], totalMinutes: Int = 0, serves: Int? = nil) {
        self.id = id ?? Recipe.slug(of: title)
        self.title = title
        self.category = category
        self.method = method
        self.source = source
        self.steps = steps
        self.items = items
        self.totalMinutes = totalMinutes
        self.serves = serves
    }
}

extension Recipe {
    /// A total time as the screens show it: "25 min", "1 hr 30 min", "8 hr".
    static func timeText(minutes: Int) -> String {
        let (hours, rest) = (minutes / 60, minutes % 60)
        if hours == 0 { return "\(minutes) min" }
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }

    /// The same, in words to speak: "25 minutes", "1 hour 30 minutes", "8 hours".
    static func spokenTime(minutes: Int) -> String {
        let (hours, rest) = (minutes / 60, minutes % 60)
        let minuteWords = "\(rest) \(rest == 1 ? "minute" : "minutes")"
        if hours == 0 { return minutes == 1 ? "1 minute" : "\(minutes) minutes" }
        let hourWords = "\(hours) \(hours == 1 ? "hour" : "hours")"
        return rest == 0 ? hourWords : "\(hourWords) \(minuteWords)"
    }

    /// A timer's length before "timer": "9-minute", "90-minute"; past 99 minutes in hours,
    /// "6-hour", "1 hour 40 minute".
    static func timerLength(minutes: Int) -> String {
        if minutes <= 99 { return "\(minutes)-minute" }
        let (hours, rest) = (minutes / 60, minutes % 60)
        return rest == 0 ? "\(hours)-hour" : "\(hours) hour \(rest) minute"
    }

    /// Every bundled recipe parsed in full, in book order. Only the tests and the checker use
    /// it; the app never parses the whole book: titles, lists, search and voice come from
    /// `RecipeIndex.bundled`, and one recipe is read when it is opened (`withID`).
    static let all: [Recipe] = RecipeBook.bundled()

    /// The recipe with this id, from its shard of the packed book (read once, then kept).
    static func withID(_ id: String) -> Recipe? { RecipeBook.recipe(id: id) }

    /// The recipe with this exact title, through the index.
    static func titled(_ title: String) -> Recipe? {
        RecipeIndex.bundled.entry(titled: title).flatMap { withID($0.id) }
    }

    /// The six the app started with, by id, for callers and tests that name one.
    static var garlicButterPasta: Recipe { named("garlic-butter-pasta") }
    static var rice: Recipe { named("rice") }
    static var hardBoiledEggs: Recipe { named("hard-boiled-eggs") }
    static var steamedBroccoli: Recipe { named("steamed-broccoli") }
    static var oatmeal: Recipe { named("oatmeal") }
    static var panSearedChicken: Recipe { named("pan-seared-chicken") }

    private static func named(_ id: String) -> Recipe {
        withID(id) ?? RecipeIndex.bundled.entries.first.flatMap { withID($0.id) } ?? Recipe(title: "Recipe", steps: [])
    }

    /// The title in lowercase words joined by hyphens: "Hard-Boiled Eggs" is "hard-boiled-eggs".
    static func slug(of title: String) -> String {
        title.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: "-")
    }

    var slug: String { id }

    /// The lines read aloud when the cook says "ingredients".
    var ingredients: [String] { items.map(\.spoken) }


    /// Where the recipe sits in the book's index; 0 for one not listed.
    var menuIndex: Int { RecipeIndex.bundled.position(of: id) ?? 0 }
}
