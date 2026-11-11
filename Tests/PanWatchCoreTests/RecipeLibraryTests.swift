import Testing
@testable import PanWatchCore

@Suite("Recipe library")
struct RecipeLibraryTests {
    @Test func libraryIsNotEmpty() {
        #expect(!Recipe.all.isEmpty)
    }

    @Test func everyTitleIsUnique() {
        let titles = Recipe.all.map(\.title)
        #expect(Set(titles).count == titles.count)
    }

    @Test func firstRecipeIsGarlicButterPasta() {
        #expect(DemoBook.recipes.first?.title == "Garlic Butter Pasta")
        #expect(DemoBook.recipes.count == 6, "the six demo dishes are all in the shipped book")
    }

    @Test func sixRecipesForThePreview() {
        #expect(Recipe.all.count >= 6)
    }

    @Test func everyRecipeListsItsIngredients() {
        for recipe in Recipe.all {
            #expect(recipe.ingredients.count >= 2, "\(recipe.title)")
        }
    }

    /// The six demo dishes each have a step the camera watches; in the whole book a watch is
    /// only on pot and pan recipes and always offers a timer.
    @Test func everyRecipeHasOneTimedAdditionTheCameraWatches() {
        for recipe in DemoBook.recipes {
            #expect(recipe.steps.contains { $0.watch != nil }, "\(recipe.title)")
        }
        for recipe in Recipe.all {
            let watched = recipe.steps.filter { $0.watch != nil }
            #expect(watched.isEmpty || recipe.method.cameraCanHelp, "\(recipe.title)")
            #expect(watched.allSatisfy { ($0.watch?.timerMinutes ?? 0) > 0 }, "\(recipe.title)")
        }
    }

    @Test func theChickenIsCheckedWithAThermometer() {
        let flip = Recipe.panSearedChicken.steps.first { $0.cue?.timerLabel == "Chicken" }
        #expect(flip?.instruction.contains("165") == true)
        #expect(flip?.instruction.contains("thermometer") == true)
    }

    @Test func theIceBathIsReadyBeforeTheEggs() {
        let cues = Recipe.hardBoiledEggs.steps.compactMap(\.cue)
        #expect(cues.map(\.secondsLeft) == [120, 0])
    }

    @Test func everyInstructionFitsLargeType() {
        for recipe in Recipe.all {
            for step in recipe.steps {
                #expect(step.instruction.count <= RecipeRules.instructionLimit, "\(recipe.title) step \(step.id)")
            }
        }
    }

    /// The screen and the spoken text never disagree on a number: every number on screen is
    /// said, and the spoken text adds only amounts and a range's upper end, never a time or a
    /// temperature the screen lacks (`RecipeRules.numberProblems`, also in the checker).
    @Test func trimmedStepsKeepEveryNumberFromTheSpokenText() {
        var breaking: Set<String> = []
        for recipe in Recipe.all {
            for step in recipe.steps {
                guard let spoken = step.spoken else { continue }
                if !RecipeRules.numberProblems(shown: step.instruction, spoken: spoken).isEmpty { breaking.insert(recipe.id) }
            }
        }
        // Converted recipes written before the rule, routed back for rewording. The list only shrinks.
        #expect(breaking.subtracting(Self.awaitingNumberRewrite).sorted() == [])
        #expect(Self.awaitingNumberRewrite.subtracting(breaking).sorted() == [], "fixed: take these off the list")
        for recipe in DemoBook.recipes { #expect(!breaking.contains(recipe.id), "\(recipe.title)") }
    }

    @Test func theNumberRuleNamesWhatDisagrees() {
        #expect(RecipeRules.numberProblems(shown: "Cook 3 minutes.", spoken: "Cook 3 to 4 minutes, stirring.").isEmpty)
        #expect(RecipeRules.numberProblems(shown: "Add the pepper.", spoken: "Add 1/4 teaspoon of pepper.").isEmpty)
        #expect(RecipeRules.numberProblems(shown: "Cook 5 minutes.", spoken: "Cook five minutes.").isEmpty)
        #expect(RecipeRules.numberProblems(shown: "Add the garlic.", spoken: "Add 2 minced garlic cloves.").isEmpty)
        let time = RecipeRules.numberProblems(shown: "Add the onion.", spoken: "Add the onion and cook 8 minutes.")
        #expect(time.count == 1 && time[0].contains("8 minutes"))
        let heat = RecipeRules.numberProblems(shown: "Flip the chicken.", spoken: "Flip it, until a thermometer reads 165 °F.")
        #expect(heat.count == 1 && heat[0].contains("165 °F"))
        let range = RecipeRules.numberProblems(shown: "Cook the pecans.", spoken: "Cook the pecans 2 to 3 minutes.")
        #expect(range.count == 1 && range[0].contains("2 minutes"))
        let dropped = RecipeRules.numberProblems(shown: "Add 4 cloves of garlic.", spoken: "Add the garlic.")
        #expect(dropped == ["the screen says 4 but \"spoken\" doesn't; say every number the screen shows."])
    }

    static let awaitingNumberRewrite: Set<String> = [
        "2-step-chicken", "african-cabbage-stew", "ambrosia", "angel-food-cake", "apple-coffee-cake",
        "apple-sage-wild-rice-stuffing", "apricot-lemon-chicken", "asian-style-steamed-salmon",
        "asparagus-lemon-sauce", "asparagus-soup", "asparagus-with-gremolata-sauce", "autumn-vegetable-succotash",
        "avocado-black-bean-taquitos", "avocado-potato-and-grilled-chicken-salad", "bacon-wrapped-oysters",
        "baked-chicken", "baked-meatballs", "baked-mostaccioli", "banaha-bread", "banana-cream",
        "banana-oatmeal-lentil-pancakes", "banana-pancakes", "banana-pancakes-with-apple-topping",
        "banana-walnut-oatmeal", "basic-waffles", "bebek-mropol", "beef-and-bean-chile-verde",
        "beef-and-vegetable-soup", "beef-pozole-soup", "beef-stroganoff", "beef-vegetable-soup-with-noodles",
        "beer-cheese-risotto", "bell-pepper-and-potato-salad", "black-bean-burgers", "black-bean-soup", "black-beans",
        "black-eyed-pea-and-collard-greens-soup", "braised-cod-with-leeks", "brown-rice-pilaf-with-sage-and-walnuts",
        "brussels-sprout-bulgur-salad", "brussels-sprouts-with-mushroom-sauce", "bulgur-veggie-chickpea-salad",
        "carbonara", "caribbean-pink-beans", "cheddar-crusted-chicken", "chicken-chile-stew",
        "chicken-mushroom-fricassee", "chicken-paprikash", "chicken-pasta-casserole",
        "chicken-red-wine-vinegar-sauce", "cold-fusilli-summer-vegetables", "collard-greens-with-smoked-duck",
        "creamy-squash-soup-apples", "curry-sauce", "easy-chicken-and-rice-casserole", "eggs-benedict",
        "exotic-ginger-cumin-chicken", "fajitas", "fast-fried-rice", "fennel-white-bean-and-kale-soup",
        "flavorful-green-beans", "grilled-steak-with-salsa-criolla", "grilled-tuna-chickpea-spinach-salad",
        "homemade-ice-cream", "lebanese-lentil-soup", "minestrone-soup", "mushroom-penne", "new-orleans-red-beans",
        "oatmeal-pancakes", "one-pot-chicken-tetrazzini", "pineapple-lentil-curry", "pizza-flavored-omelet",
        "quebec-shepherds-pie", "red-beans-and-rice", "risengroed-rice-porridge", "roasted-beets-orange-sauce",
        "schnitzel", "sizzling-chicken-and-vegetables", "spiced-apple-pancakes", "spinach-raisins-pine-nuts",
        "spinach-rice-casserole", "stuffed-vegetables", "sweet-potato-and-peanut-soup", "tofu-and-cashew-chow-mein",
        "turmeric-flatbread", "vegetable-stew",
    ]

    /// The checker's lines without the number rule's, for the recipes awaiting that rewrite.
    static func withoutAwaitedNumberLines(_ lines: [String]) -> [String] {
        lines.filter { line in
            let id = String(line.prefix { $0 != "." })
            let numberRule = line.contains("but \"spoken\" doesn't;") || line.contains("but the screen doesn't;")
            return !(numberRule && awaitingNumberRewrite.contains(id))
        }
    }

    @Test func everyRecipePassesTheChecks() {
        for recipe in Recipe.all {
            #expect(recipe.problems().isEmpty, "\(recipe.title)")
        }
    }
}
