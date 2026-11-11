import Foundation
import Testing
@testable import PanWatchCore

/// Finding one dish by voice among many: distinctive words, an exact title first, one
/// question when several match, and search when none does.
@Suite("Recipe voice")
struct RecipeVoiceTests {
    /// A made-up book of sixty, as the full recipe book will be.
    static let sixty = [
        "Garlic Butter Pasta", "Rice", "Fried Rice", "Rice Pudding", "Hard-Boiled Eggs", "Soft-Boiled Eggs",
        "Scrambled Eggs", "Oatmeal", "Pancakes", "French Toast", "Steamed Broccoli", "Roasted Carrots",
        "Green Beans with Almonds", "Mashed Potatoes", "Baked Potatoes", "Pan-Seared Chicken", "Chicken Soup",
        "Chicken Stir-Fry", "Lemon Chicken", "Chicken with Rice", "Chicken Tacos", "Beef Chili", "Beef Stew",
        "Pork Chops", "Meatballs", "Sloppy Joes", "Pan-Seared Salmon", "Baked Cod", "Shrimp Scampi", "Fish Tacos",
        "Tuna Salad", "Lentil Soup", "Black Bean Soup", "Tomato Soup", "Minestrone", "Split Pea Soup",
        "Red Lentil Curry", "Refried Beans", "Chickpea Salad", "Hummus", "Spaghetti with Meat Sauce",
        "Macaroni and Cheese", "Penne with Pesto", "Quinoa", "Couscous", "Polenta", "Grilled Cheese",
        "Egg Fried Rice", "Vegetable Stir-Fry", "Sauteed Spinach", "Corn on the Cob", "Butternut Squash Soup",
        "Pork Fried Rice", "Teriyaki Chicken", "Chicken Noodle Soup", "Beef Tacos", "Banana Bread",
        "Overnight Oats", "Sweet Potato Fries", "Garlic Shrimp",
    ]

    private func match(_ text: String, choosing: Bool = true) -> VoiceCommand.RecipeMatch {
        VoiceCommand.recipeMatch(VoiceCommand.words(in: text), choosing: choosing, titles: Self.sixty)
    }

    @Test func theMadeUpBookHasSixtyDifferentTitles() {
        #expect(Self.sixty.count == 60)
        #expect(Set(Self.sixty.map(VoiceCommand.distinctiveWords)).count == 60)
    }

    @Test func makeTheLentilSoup() {
        #expect(match("make the lentil soup") == .one("Lentil Soup"))
    }

    @Test func letsDoTheChickenStirFry() {
        #expect(match("let's do the chicken stir fry") == .one("Chicken Stir-Fry"))
    }

    @Test func anExactTitleWinsCookRiceIsRice() {
        #expect(match("cook rice") == .one("Rice"))
        #expect(match("make the fried rice") == .one("Fried Rice"))
    }

    @Test func everyTitleSaidAfterMakeFindsItself() {
        for title in Self.sixty {
            #expect(match("make the \(title)") == .one(title), "\(title)")
        }
    }

    @Test func pluralsAndFillerAreForgiven() {
        #expect(match("make the scrambled egg") == .one("Scrambled Eggs"))
        #expect(match("let's make pancake") == .one("Pancakes"))
        #expect(match("cook chicken and rice") == .one("Chicken with Rice"))
        #expect(match("make macaroni with cheese") == .one("Macaroni and Cheese"))
    }

    @Test func aWordSharedByManyAsksWhichInBookOrder() {
        guard case .several(let titles) = match("make the chicken") else {
            Issue.record("expected several"); return
        }
        #expect(titles.count == 8)
        #expect(Array(titles.prefix(3)) == ["Pan-Seared Chicken", "Chicken Soup", "Chicken Stir-Fry"])
    }

    @Test func theQuestionNamesAtMostThreeInPlainWords() {
        #expect(VoiceCommand.whichRecipeQuestion(["Chicken Soup", "Chicken Stir-Fry", "Lemon Chicken"])
            == "Chicken soup, chicken stir-fry, or lemon chicken?")
        // More than three: one line, and the list shows them.
        #expect(VoiceCommand.whichRecipeQuestion(["Chicken Soup", "Chicken Stir-Fry", "Lemon Chicken", "Chicken Tacos"])
            == "I found several. Here they are.")
        #expect(VoiceCommand.whichRecipeQuestion(["Rice Pudding", "Fried Rice"]) == "Rice pudding or fried rice?")
        #expect(PlainWords.bannedWords(in: VoiceCommand.whichRecipeQuestion(Self.sixty)).isEmpty)
    }

    @Test func theNextUtterancePicksOne() {
        let asked = ["Chicken Soup", "Chicken Stir-Fry", "Lemon Chicken"]
        #expect(VoiceCommand.pick("lemon", among: asked) == "Lemon Chicken")
        #expect(VoiceCommand.pick("the soup", among: asked) == "Chicken Soup")
        #expect(VoiceCommand.pick("the second one", among: asked) == "Chicken Stir-Fry")
        #expect(VoiceCommand.pick("the last one", among: asked) == "Lemon Chicken")
        #expect(VoiceCommand.pick("chicken", among: asked) == nil)
        #expect(VoiceCommand.parse("stir fry please", choosing: asked) == .makeRecipe("Chicken Stir-Fry"))
        #expect(VoiceCommand.parse("next step", choosing: asked) == .next)
    }

    @Test func noMatchSearchesForWhatWasHeard() {
        #expect(VoiceCommand.parse("make the lasagna") == .findRecipe("lasagna"))
        #expect(VoiceCommand.parse("let's cook beef stroganoff", book: DemoBook.voice) == .findRecipe("beef stroganoff"))
        #expect(match("make the lasagna") == .none)
    }

    @Test func talkAfterMakeIsNotASearch() {
        #expect(VoiceCommand.wantedDish(VoiceCommand.words(in: "make sure it's hot")) == nil)
        #expect(VoiceCommand.parse("cook it longer") == nil)
        #expect(VoiceCommand.parse("do it") == .yes)
        #expect(VoiceCommand.parse("the pasta looks good") == nil)
        #expect(match("the chicken looks good", choosing: false) == .none)
    }

    @Test func oneWordOnARecipeScreenAsksWhenSeveralShareIt() {
        let titles = ["Chicken Soup", "Lemon Chicken"]
        #expect(VoiceCommand.recipeMatch(["chicken"], choosing: true, titles: titles) == .several(titles))
        #expect(VoiceCommand.parse("rice", screen: .recipeList) == .makeRecipe("Rice"))
        #expect(VoiceCommand.parse("rice", screen: .cook) == nil)
    }

    @Test func theSixKeepTodaysBehavior() {
        let cases: [(String, AppScreen, String)] = [
            ("make the rice", .recipes, "Rice"), ("let's do pasta", .recipes, "Garlic Butter Pasta"),
            ("cook the eggs please", .recipes, "Hard-Boiled Eggs"), ("make the chicken", .cook, "Pan-Seared Chicken"),
            ("steamed broccoli", .cook, "Steamed Broccoli"), ("lets make oatmeal", .cook, "Oatmeal"),
            ("eggs", .recipes, "Hard-Boiled Eggs"),
        ]
        for (text, screen, title) in cases {
            #expect(VoiceCommand.parse(text, screen: screen, book: DemoBook.voice) == .makeRecipe(title), "\(text)")
        }
    }

    @Test func matchingSixtyTitlesStaysFast() {
        let phrases = ["make the lentil soup", "let's do the chicken stir fry", "cook rice", "make the chicken", "make the lasagna"]
            .map(VoiceCommand.words)
        let book = VoiceTitles(Self.sixty)
        let start = Date()
        for round in 0..<400 {
            _ = VoiceCommand.recipeMatch(phrases[round % phrases.count], choosing: true, in: book)
        }
        // 400 utterances well under a second, so one is far under a millisecond's worry.
        #expect(Date().timeIntervalSince(start) < 1.0)
    }
}
