import Testing
@testable import PanWatchCore

/// The checker gaps converters hit writing real recipes (Recipes/README.md).
struct RecipeGapsTests {
    @Test func countsAndContainersAreUnits() {
        for unit in ["square", "block", "scoop", "spray", "splash", "knob", "clove", "bulb", "rack", "tin",
                     "carton", "tub", "pouch", "bar", "round", "sheet"] {
            #expect(RecipeRules.amountProblem("1 \(unit)") == nil, "\(unit)")
            #expect(RecipeRules.isUnit(unit + (unit.hasSuffix("sh") || unit.hasSuffix("ch") ? "es" : "s")), "\(unit) plural")
        }
    }

    @Test func asNeededAndDecimalsAreAmounts() {
        #expect(RecipeRules.amountProblem("as needed") == nil)
        #expect(RecipeRules.amountProblem("14.5 ounces") == nil)
        #expect(RecipeRules.amountProblem("plenty") != nil)
    }

    @Test func aWatchStepMayStartWithAnAdverb() {
        #expect(RecipeRules.addsSomething("Gently add the eggs to the water."))
        #expect(RecipeRules.addsSomething("Slowly pour in the broth."))
        #expect(RecipeRules.addsSomething("Carefully drop the dumplings in."))
        #expect(!RecipeRules.addsSomething("Gently stir the sauce."))
    }

    @Test func rangesAndIntervalsAndShortTimes() {
        #expect(RecipeRules.statedTimes(in: "Cook on low 3 to 4 hours.").first?.covered.contains(180) == true)
        #expect(RecipeRules.statedTimes(in: "Cook 60 seconds.").isEmpty)
        #expect(RecipeRules.statedTimes(in: "Cook 120 seconds.").map(\.minutes) == [2])
        #expect(RecipeRules.statedTimes(in: "Bake, stirring every 15 minutes.").isEmpty)
        #expect(RecipeRules.statedTimes(in: "Stir every 15 to 20 minutes.").isEmpty)
    }

    @Test func settingsAndMeasuredTemperaturesPass() {
        for text in ["Heat the grill to 350 °F.", "Heat the griddle to 375 °F.", "Heat the oil to 360 °F.",
                     "Cook the syrup to 270 °F.", "Cook the candy to 300 °F.", "Heat the water to 120 to 130 °F.",
                     "Dissolve the yeast in 110 to 115 °F water.", "Keep the oil between 325 and 350 °F.",
                     "Cook the curd until it reaches about 185 °F.", "Stir until a thermometer reads 180 °F."] {
            #expect(RecipeRules.wordProblems(text).isEmpty, "\(text)")
        }
        #expect(!RecipeRules.wordProblems("The cake is 200 °F inside.").isEmpty)
    }

    @Test func aCueAboutTheNextActionIsNoClaim() {
        #expect(RecipeRules.wordProblems("Cook until it is ready to turn.").isEmpty)
        #expect(RecipeRules.wordProblems("When they are ready to flip, bubbles show.").isEmpty)
        #expect(!RecipeRules.wordProblems("The chicken is ready.").isEmpty)
        #expect(!RecipeRules.wordProblems("It is ready to eat.").isEmpty)
    }

    @Test func aRestAfterCookingWithItsTimerIsAStep() {
        #expect(RecipeRules.instructionProblems("Let it cool for 10 minutes.", hasTimer: true).isEmpty)
        #expect(RecipeRules.instructionProblems("Let it cool in the pan for 10 minutes.", hasTimer: true).isEmpty)
        #expect(!RecipeRules.instructionProblems("Let it cool for 10 minutes.").isEmpty)
        #expect(!RecipeRules.instructionProblems("Wait 10 minutes.", hasTimer: true).isEmpty)
    }

    @Test func titlesRunTo48WithAGloss() {
        #expect(RecipeRules.titleLimit == 48)
        #expect(RecipeRules.titleProblems("Risengrød (rice porridge)").isEmpty)
        #expect(RecipeRules.titleProblems("Chicken and Rice with Lemon and Garlic Sauce").isEmpty)
        #expect(!RecipeRules.titleProblems(String(repeating: "Long ", count: 10)).isEmpty)
    }
}
