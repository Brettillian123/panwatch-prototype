import Foundation
import Testing
@testable import PanWatchCore

/// A made-up book of 1,500 plausible dishes for testing only, never app data: titles share
/// words the way a real book's do ("Chicken" is in 150 of them).
enum SyntheticBook {
    static let flavors = ["Lemon", "Garlic", "Smoky", "Spicy", "Honey", "Herb", "Ginger", "Sesame",
                          "Pepper", "Maple", "Basil", "Chili", "Mustard", "Tomato", "Butter"]
    static let mains = ["Chicken", "Beef", "Pork", "Salmon", "Shrimp", "Tofu", "Bean", "Lentil", "Mushroom", "Potato"]
    static let dishes = ["Soup", "Stew", "Skillet", "Bowl", "Salad", "Tacos", "Pasta", "Rice", "Wraps", "Bake"]

    static func category(main: String, dish: String) -> RecipeCategory {
        switch dish {
        case "Soup", "Stew": return .soups
        case "Salad": return .salads
        case "Tacos", "Wraps": return .sandwichesAndWraps
        case "Pasta", "Rice": return .pastaAndGrains
        default:
            switch main {
            case "Chicken": return .chicken
            case "Beef", "Pork": return .beefAndPork
            case "Salmon", "Shrimp": return .fish
            case "Tofu", "Bean", "Lentil": return .beansAndLentils
            default: return .vegetables
            }
        }
    }

    /// 1,500 entries: every flavor, main and dish.
    static let entries: [RecipeEntry] = {
        var out: [RecipeEntry] = []
        for (f, flavor) in flavors.enumerated() {
            for (m, main) in mains.enumerated() {
                for (d, dish) in dishes.enumerated() {
                    let title = "\(flavor) \(main) \(dish)"
                    let minutes = 10 + (f * 7 + m * 3 + d * 5) % 80
                    out.append(RecipeEntry(
                        id: Recipe.slug(of: title), title: title, category: category(main: main, dish: dish),
                        method: dish == "Bake" ? .oven : dish == "Salad" ? .noHeat : (d.isMultiple(of: 2) ? .pot : .pan),
                        totalMinutes: minutes, serves: 2 + (f + m) % 5,
                        ingredients: [main.lowercased() == "bean" ? "black beans" : main.lowercased(), flavor.lowercased(), "olive oil", "salt", "onion"],
                        source: f.isMultiple(of: 3) ? "Sous Vision" : "Test Kitchen", hasPhoto: false))
                }
            }
        }
        return out
    }()

    static let index = RecipeIndex(entries: entries)

    /// `count` recipe files in a fresh temp folder, each the rice recipe under a new name.
    static func folder(count: Int) throws -> URL {
        let source = try #require(RecipeBook.bundledFolder())
        let template = try String(contentsOf: source.appendingPathComponent("rice.json"), encoding: .utf8)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("synthetic-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for entry in entries.prefix(count) {
            let text = template
                .replacingOccurrences(of: #""id": "rice""#, with: "\"id\": \"\(entry.id)\"")
                .replacingOccurrences(of: #""title": "Rice""#, with: "\"title\": \"\(entry.title)\"")
            try text.write(to: folder.appendingPathComponent(entry.id + ".json"), atomically: false, encoding: .utf8)
        }
        return folder
    }

    static func milliseconds(_ work: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        work()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    /// Timing limits hold in a release build; a debug build gets ten times the room.
    static var slack: Double {
        #if DEBUG
        10
        #else
        1
        #endif
    }
}

@Suite struct RecipeScaleTests {
    let book = SyntheticBook.index

    // MARK: The index

    @Test func theBookHasFifteenHundredWithSharedWords() {
        #expect(book.entries.count == 1500)
        #expect(book.titles.filter { $0.contains("Chicken") }.count == 150)
        #expect(Set(book.titles).count == 1500)
    }

    @Test func theIndexRoundTripsAndLoadsFast() throws {
        let data = RecipeIndex.encode(SyntheticBook.entries)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("index-\(UUID().uuidString).json")
        try data.write(to: file)
        var loaded: RecipeIndex?
        let ms = SyntheticBook.milliseconds {
            loaded = FileManager.default.contents(atPath: file.path).flatMap { try? RecipeIndex.decode($0) }
        }
        print("RecipeScale index load ms: \(String(format: "%.1f", ms)) for 1500 (\(data.count / 1024) KB)")
        #expect(loaded?.entries == book.entries)
        #expect(ms < 100 * SyntheticBook.slack)
    }

    @Test func theCommittedIndexMatchesTheRecipeFiles() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = repo.appendingPathComponent("PanWatch/Core/Recipes")
        let built = RecipeIndex.build(folder: folder, assets: repo.appendingPathComponent("PanWatch/Assets.xcassets"))
        let data = try #require(FileManager.default.contents(atPath: folder.appendingPathComponent("index.json").path))
        let committed = try RecipeIndex.decode(data)
        #expect(committed.entries == RecipeIndex(entries: built).entries,
                "index.json is out of date: run swift run PanWatchScenarios --check-recipes --write-index")
        #expect(RecipeIndex.bundled.entries == committed.entries)
        #expect(RecipeIndex.bundled.entries.count == RecipeBook.load(from: folder).recipes.count)
    }

    @Test func oneRecipeIsReadWhenOpenedAndKept() throws {
        let folder = try SyntheticBook.folder(count: 3)
        let id = SyntheticBook.entries[1].id
        let recipe = try #require(RecipeBook.recipe(id: id, in: folder))
        #expect(recipe.title == SyntheticBook.entries[1].title)
        try FileManager.default.removeItem(at: folder.appendingPathComponent(id + ".json"))
        #expect(RecipeBook.recipe(id: id, in: folder) == recipe)
        #expect(RecipeBook.recipe(id: "no-such-dish", in: folder) == nil)
    }

    // MARK: Search

    @Test func searchIsFastOnFifteenHundred() {
        var found: [RecipeEntry] = []
        let ms = SyntheticBook.milliseconds { found = book.search("chiken stew") }
        print("RecipeScale search ms: \(String(format: "%.1f", ms)) for 1500")
        #expect(found.count == 15)
        #expect(ms < 20 * SyntheticBook.slack)
    }

    @Test func searchRanksStartsWithThenContainsThenIngredient() {
        let found = book.search("lemon")
        #expect(found.count == 100)
        #expect(found.allSatisfy { $0.title.hasPrefix("Lemon") })
        let chicken = book.search("chicken")
        #expect(chicken.count == 150)
        let tofu = book.search("onion tofu")
        #expect(tofu.count == 150 && tofu.allSatisfy { $0.title.contains("Tofu") })
        // Starts-with before contains: "Bean" titles never start with "bean"; "black beans" is an ingredient.
        let beans = book.search("black beans")
        #expect(beans.count == 150)
    }

    @Test func searchStartsWithComesFirst() {
        let index = RecipeIndex(entries: [
            entry("Smoky Pork Skillet", ["pork"]), entry("Pork Tacos", ["pork"]), entry("Beef Stew", ["pork fat"]),
        ])
        #expect(index.search("pork").map(\.title) == ["Pork Tacos", "Smoky Pork Skillet", "Beef Stew"])
    }

    @Test func searchForgivesPluralsAndOneLetter() {
        #expect(book.search("tacos").count == 150)
        #expect(book.search("taco").count == 150)
        #expect(book.search("salmun").count == 150)
        #expect(book.search("zzzz").isEmpty)
    }

    @Test func searchStaysInsideTheFilter() {
        let soups = book.search("chicken", within: .category(.soups))
        #expect(soups.count == 30 && soups.allSatisfy { $0.category == .soups })
        let quick = book.search("", within: .quick)
        #expect(!quick.isEmpty && quick.allSatisfy { $0.isQuick })
    }

    // MARK: Voice

    @Test func voiceMatchingIsFastOnFifteenHundred() {
        var match = VoiceCommand.RecipeMatch.none
        let ms = SyntheticBook.milliseconds {
            match = VoiceCommand.recipeMatch(["make", "lemon", "chicken", "stew"], choosing: true, titles: book.titles)
        }
        print("RecipeScale voice match ms: \(String(format: "%.1f", ms)) for 1500")
        #expect(match == .one("Lemon Chicken Stew"))
        #expect(ms < 20 * SyntheticBook.slack)
    }

    @Test func voiceExactTitleWins() {
        let titles = book.titles + ["Chicken Stew"]
        #expect(VoiceCommand.recipeMatch(["make", "chicken", "stew"], choosing: true, titles: titles) == .one("Chicken Stew"))
    }

    @Test func voiceTwoOrThreeEqualAsksOnceNamingThem() {
        let titles = ["Lemon Chicken Soup", "Lemon Chicken Stew", "Beef Stew"] + book.titles.filter { !$0.hasPrefix("Lemon Chicken") }
        guard case .several(let found) = VoiceCommand.recipeMatch(["make", "lemon", "chicken"], choosing: true, titles: titles) else {
            Issue.record("expected several")
            return
        }
        #expect(found == ["Lemon Chicken Soup", "Lemon Chicken Stew"])
        #expect(VoiceCommand.whichRecipeQuestion(found) == "Lemon chicken soup or lemon chicken stew?")
    }

    @Test func voiceMoreThanThreeShowsTheList() {
        guard case .several(let found) = VoiceCommand.recipeMatch(["make", "lemon", "chicken"], choosing: true, titles: book.titles) else {
            Issue.record("expected several")
            return
        }
        #expect(found.count == 10)
        #expect(VoiceCommand.whichRecipeQuestion(found) == "I found several. Here they are.")
    }

    @Test func voicePicksFromTheListByPlaceOrName() {
        let shown = ["Lemon Chicken Soup", "Lemon Chicken Stew", "Lemon Chicken Skillet", "Lemon Chicken Bowl", "Lemon Chicken Salad"]
        #expect(VoiceCommand.pick("the first one", among: shown) == "Lemon Chicken Soup")
        #expect(VoiceCommand.pick("number two", among: shown) == "Lemon Chicken Stew")
        #expect(VoiceCommand.pick("number one", among: shown) == "Lemon Chicken Soup")
        #expect(VoiceCommand.pick("the 4th", among: shown) == "Lemon Chicken Bowl")
        #expect(VoiceCommand.pick("the last one", among: shown) == "Lemon Chicken Salad")
        #expect(VoiceCommand.pick("the skillet", among: shown) == "Lemon Chicken Skillet")
    }

    @Test func voiceNoMatchIsNone() {
        #expect(VoiceCommand.recipeMatch(["make", "lasagna"], choosing: true, titles: book.titles) == .none)
        #expect(VoiceCommand.wantedDish(["make", "lasagna"]) == "lasagna")
    }

    @Test func voiceDistinctiveWordsPickOne() {
        #expect(VoiceCommand.recipeMatch(["cook", "the", "maple", "salmon", "tacos"], choosing: true, titles: book.titles)
                == .one("Maple Salmon Tacos"))
        // Ordinary talk naming one word of many titles is not a choice.
        #expect(VoiceCommand.recipeMatch(["the", "chicken", "looks", "good"], choosing: false, titles: book.titles) == .none)
    }

    // MARK: The checker at batch size

    @Test func theCheckerRunsABatchAndSummarizes() throws {
        let folder = try SyntheticBook.folder(count: 300)
        var report = RecipeBook.CheckReport()
        let ms = SyntheticBook.milliseconds { report = RecipeBook.checkReport(folder: folder) }
        print("RecipeScale checker ms: \(Int(ms)) for 300 files")
        #expect(report.files == 300 && report.passed == 300 && report.lines.isEmpty)
        #expect(report.summary.first == "300 files, 300 passed, 0 failed.")
        // One broken file, checked alone with --only.
        let bad = SyntheticBook.entries[5].id
        let path = folder.appendingPathComponent(bad + ".json")
        let text = try String(contentsOf: path, encoding: .utf8)
            .replacingOccurrences(of: #", "timer": { "label": "Rest", "minutes": 5 }"#, with: "")
        try text.write(to: path, atomically: false, encoding: .utf8)
        let only = RecipeBook.checkReport(folder: folder, only: [bad, SyntheticBook.entries[6].id])
        #expect(only.files == 2 && only.failedFiles == [bad + ".json"])
        #expect(only.byRule.map(\.rule) == ["it says N minutes, but no step has a N-minute timer"])
        #expect(RecipeBook.checkReport(folder: folder, only: ["missing-dish"]).failedFiles == ["missing-dish.json"])
    }

    @Test func anOffHeatWaitNeedsATimer() {
        let recipe = Recipe(title: "Resting Test", steps: [
            RecipeStep(id: 1, instruction: "Cook the steak.", watch: nil),
            RecipeStep(id: 2, instruction: "Let it rest for 5 minutes before slicing.", watch: nil),
        ])
        #expect(recipe.authoringProblems().contains { $0.contains("5-minute timer") })
        let timed = Recipe(title: "Resting Test", steps: [
            RecipeStep(id: 1, instruction: "Cook the steak.", watch: nil),
            RecipeStep(id: 2, instruction: "Let it rest for 5 minutes before slicing.", watch: nil, timer: StepTimer(label: "Rest", minutes: 5)),
        ])
        #expect(!timed.authoringProblems().contains { $0.contains("5-minute timer") })
    }

    // MARK: Categories and credits

    @Test func fourteenPlainCategoriesEachWithItsOwnSymbol() {
        #expect(RecipeCategory.allCases.count == 14)
        #expect(Set(RecipeCategory.allCases.map(\.symbol)).count == 14)
        #expect(RecipeCategory.allCases.allSatisfy { PlainWords.bannedWords(in: $0.title).isEmpty })
        #expect(RecipeFilter.chips.prefix(3).map(\.title) == ["All", "Under 20 min", "Stovetop"])
        #expect(RecipeFilter.chips.count == 17)
    }

    @Test func creditsNameEachSourceOnce() {
        let sources = [RecipeSourceCredit(name: "Test Kitchen", credit: "Recipes adapted from Test Kitchen.", url: "https://example.com")]
        let notices = Credits.recipeNotices(book.entries, sources: sources)
        #expect(notices.map(\.title) == ["Test Kitchen"])
        #expect(notices.first?.text == "Recipes adapted from Test Kitchen.\nhttps://example.com")
        #expect(Credits.recipeNotices(RecipeIndex.bundled.entries, sources: []).isEmpty)
    }

    // MARK: Cook mode's plain timer

    @Test func aPlainTimerIsOfferedWhenItsStepOpens() throws {
        let step = RecipeStep(id: 2, instruction: "Bake for 10 minutes.", watch: nil, timer: StepTimer(label: "Bake", minutes: 10))
        let offer = try #require(TimerOffer.onOpen(step, started: false))
        #expect(offer.caption == "This step takes 10 minutes.")
        #expect(offer.question == "Start a 10-minute timer?")
        #expect(offer.spoken == "This step takes 10 minutes. Start a 10 minute timer?")
        #expect(offer.watch.timerLabel == "Bake" && offer.watch.timerMinutes == 10)
    }

    @Test func aPlainTimerIsNotOfferedTwiceOrOverTheCamera() {
        let step = RecipeStep(id: 2, instruction: "Bake for 10 minutes.", watch: nil, timer: StepTimer(label: "Bake", minutes: 10))
        #expect(TimerOffer.onOpen(step, started: true) == nil)
        #expect(TimerOffer.onOpen(step, started: false, running: ["bake"]) == nil)
        let watched = Recipe.garlicButterPasta.steps[1]
        #expect(TimerOffer.onOpen(watched, started: false) == nil)
        #expect(TimerOffer.onOpen(Recipe.garlicButterPasta.steps[0], started: false) == nil)
        #expect(TimerOffer.seen(watched.watch!).caption == "Looks like the pasta went in.")
        #expect(TimerOffer(label: "Rest", minutes: 1, plain: true).caption == "This step takes 1 minute.")
    }

    @Test func theBundledRecipesOfferTheirRestTimers() {
        let rice = Recipe.rice
        let offers = rice.steps.compactMap { TimerOffer.onOpen($0, started: false) }
        #expect(offers.map(\.minutes) == [5])
    }

    private func entry(_ title: String, _ ingredients: [String]) -> RecipeEntry {
        RecipeEntry(id: Recipe.slug(of: title), title: title, category: .beefAndPork, method: .pan, totalMinutes: 20,
                    serves: 2, ingredients: ingredients, source: "Sous Vision", hasPhoto: false)
    }
}
