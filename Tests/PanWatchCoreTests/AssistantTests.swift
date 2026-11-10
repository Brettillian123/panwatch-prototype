import Testing
@testable import PanWatchCore

/// The assistant's pure parts: the context it's given, its tools, the rails on its replies
/// and the food-safety table. Research 16, section 3.
@Suite("Assistant")
struct AssistantTests {
    static let pasta = Recipe.garlicButterPasta

    static func context(step: Int = 2, offer: String? = nil, timers: [IntentContext.RunningTimer] = []) -> AssistantContext {
        let recipe = pasta
        return AssistantContext(
            recipe: recipe.title,
            stepNumber: step,
            stepCount: recipe.steps.count,
            step: recipe.steps[step - 1].instruction,
            nextStep: step < recipe.steps.count ? recipe.steps[step].instruction : nil,
            ingredients: recipe.ingredients,
            timers: timers,
            offer: offer,
            facts: recipe.steps.map(\.spokenText) + recipe.steps.compactMap(\.watch).map { "\($0.timerMinutes) minutes" }
        )
    }

    // MARK: Context

    @Test func promptCarriesTheRecipeTheStepsTheTimersAndTheOffer() {
        let prompt = Self.context(step: 2, offer: "Looks like the pasta went in. Start a 9 minute timer?",
                                  timers: [.init(label: "Pasta", secondsLeft: 480)]).prompt(heard: "how much salt")
        #expect(prompt.contains("Recipe: Garlic Butter Pasta, step 2 of 5"))
        #expect(prompt.contains("Current step: Add 1 pound of pasta"))
        #expect(prompt.contains("Next step: Melt 3 tablespoons of butter"))
        #expect(prompt.contains("Ingredients: 1 pound of pasta; 1 tablespoon of salt"))
        #expect(prompt.contains("Running timers: Pasta, 8 min left"))
        #expect(prompt.contains("Offer waiting: Looks like the pasta went in."))
        #expect(prompt.hasSuffix("The cook said: \"how much salt\""))
    }

    @Test func promptOnTheLastStepWithNothingRunning() {
        let prompt = Self.context(step: 5).prompt(heard: "what now")
        #expect(prompt.contains("Next step: none, this is the last step"))
        #expect(prompt.contains("Running timers: none"))
        #expect(prompt.contains("Offer waiting: none"))
    }

    @Test func promptKeepsTheIngredientListSmall() {
        var context = Self.context()
        context.ingredients = (1...20).map { "ingredient \($0) " + String(repeating: "x", count: 100) }
        let line = context.prompt(heard: "hi").split(separator: "\n").first { $0.hasPrefix("Ingredients:") } ?? ""
        #expect(line.components(separatedBy: "; ").count == AssistantContext.ingredientLimit)
        #expect(line.count < AssistantContext.ingredientLimit * (AssistantContext.ingredientLength + 2) + 20)
    }

    @Test func promptLeavesTheFactsOut() {
        var context = Self.context()
        context.facts = ["a secret line"]
        #expect(!context.prompt(heard: "hi").contains("a secret line"))
    }

    @Test func instructionsSetTheScopeAndStaySmall() {
        let text = AssistantContext.instructions
        #expect(text.contains(AssistantRails.outOfScope))
        #expect(text.contains("Never say food is done"))
        #expect(text.contains("answer exactly: none"))
        // About 4 characters a token: well under the 150-token share research 16 sets.
        #expect(text.count < 900)
    }

    @Test func aReplyStillAppliesOnlyToTheSameRecipeStepAndOffer() {
        let asked = Self.context(step: 2)
        var later = asked
        later.timers = [.init(label: "Pasta", secondsLeft: 30)]
        #expect(asked.stillApplies(to: later))
        #expect(!asked.stillApplies(to: Self.context(step: 3)))
        #expect(!asked.stillApplies(to: Self.context(step: 2, offer: "Start a timer?")))
        var other = asked
        other.recipe = "Rice"
        #expect(!asked.stillApplies(to: other))
    }

    // MARK: Tools

    @Test func stepToolMapsToTheStepCommands() {
        #expect(AssistantAction.step("next", number: nil)?.command == .next)
        #expect(AssistantAction.step("previous", number: nil)?.command == .back)
        #expect(AssistantAction.step("goToStep", number: 4)?.command == .goToStep(4))
        #expect(AssistantAction.step("goToStep", number: nil) == nil)
        #expect(AssistantAction.step("repeatStep", number: nil)?.command == .repeatStep)
        #expect(AssistantAction.step("startOver", number: nil)?.command == .startOver)
        #expect(AssistantAction.step("jump", number: 2) == nil)
        for action in AssistantAction.stepActions {
            #expect(AssistantAction.step(action, number: 1) != nil)
        }
    }

    @Test func timerToolCarriesMinutesAndNames() {
        #expect(AssistantAction.timer("startStepTimer", minutes: nil, name: nil)?.command == .startTimer)
        #expect(AssistantAction.timer("set", minutes: 10, name: nil)?.command == .setTimer(minutes: 10))
        #expect(AssistantAction.timer("set", minutes: 10, name: "  ") == .setTimer(minutes: 10, name: nil))
        let named = AssistantAction.timer("set", minutes: 7, name: "eggs")
        #expect(named == .setTimer(minutes: 7, name: "eggs"))
        // The app starts a named timer itself, with its name.
        #expect(named?.command == nil)
        #expect(AssistantAction.timer("set", minutes: nil, name: "eggs") == nil)
        #expect(AssistantAction.timer("set", minutes: 0, name: nil) == nil)
        #expect(AssistantAction.timer("cancel", minutes: nil, name: "pasta")?.command == .cancelNamedTimer("pasta"))
        #expect(AssistantAction.timer("cancel", minutes: nil, name: nil)?.command == .cancelTimer)
        #expect(AssistantAction.timer("timeLeft", minutes: nil, name: nil)?.command == .timeLeft)
        for action in AssistantAction.timerActions where action != "set" {
            #expect(AssistantAction.timer(action, minutes: nil, name: nil) != nil)
        }
    }

    @Test func recipeToolChoosesOnlyTheAppsRecipes() {
        #expect(AssistantAction.recipe("readIngredients", name: nil)?.command == .ingredients)
        #expect(AssistantAction.recipe("openRecipes", name: nil)?.command == .showRecipes)
        #expect(AssistantAction.recipe("cameraOn", name: nil)?.command == .camera(on: true))
        #expect(AssistantAction.recipe("cameraOff", name: nil)?.command == .camera(on: false))
        #expect(AssistantAction.recipe("choose", name: "garlic butter pasta")?.command == .makeRecipe(Recipe.garlicButterPasta.title))
        #expect(AssistantAction.recipe("choose", name: "rice")?.command == .makeRecipe(Recipe.rice.title))
        #expect(AssistantAction.recipe("choose", name: "the chicken")?.command == .makeRecipe(Recipe.panSearedChicken.title))
        #expect(AssistantAction.recipe("choose", name: "lasagna") == nil)
        #expect(AssistantAction.recipe("choose", name: nil) == nil)
        for action in AssistantAction.recipeActions where action != "choose" {
            #expect(AssistantAction.recipe(action, name: nil) != nil)
        }
    }

    @Test func appToolNamesMatchTheAppsToolEnum() {
        // `AppTool.Command` in Session/CookAssistant.swift lists these, in this order.
        #expect(AssistantAction.appCommands.map(\.rawValue) == [
            "yes", "no", "startWatching", "whereAmI", "clearDone", "drawPan", "switchCamera", "showVoices",
            "nextVoice", "useThisVoice", "useMyVoice", "quiet", "talk", "stopListening", "help", "settings",
            "details", "done",
        ])
        #expect(AssistantAction.app("yes")?.command == .yes)
        #expect(AssistantAction.app("help")?.command == .help)
        #expect(AssistantAction.app("quiet")?.command == .quiet)
        // The other tools cover these, and none is never a command.
        #expect(AssistantAction.app("next") == nil)
        #expect(AssistantAction.app("none") == nil)
    }

    @Test func everyToolActionIsACommandTheCookCouldSay() {
        let all: [AssistantAction] = [
            .next, .back, .goToStep(2), .repeatStep, .startOver, .startStepTimer, .setTimer(minutes: 5, name: nil),
            .cancelTimer(name: nil), .cancelTimer(name: "pasta"), .timeLeft, .ingredients, .showRecipes,
            .chooseRecipe("Rice"), .camera(on: true), .camera(on: false),
        ] + AssistantAction.appCommands.map(AssistantAction.app)
        for action in all {
            #expect(action.command != nil, "\(action)")
        }
    }

    @Test func startingTheStepTimerIsTheSameCommandThatAcceptsAnOffer() {
        // CookSession's startStepTimer accepts a waiting offer, so a tool can't go around it.
        #expect(AssistantAction.startStepTimer.command == .startTimer)
    }

    @Test func toolProblemsAreSaidBackToTheModel() {
        let context = Self.context(step: 1)
        #expect(AssistantAction.goToStep(9).problem(in: context) == "This recipe has 5 steps.")
        #expect(AssistantAction.goToStep(0).problem(in: context) != nil)
        #expect(AssistantAction.goToStep(5).problem(in: context) == nil)
        #expect(AssistantAction.back.problem(in: context) == "This is the first step.")
        #expect(AssistantAction.next.problem(in: Self.context(step: 5)) == "This is the last step.")
        #expect(AssistantAction.timeLeft.problem(in: context) == "No timers are running.")
        #expect(AssistantAction.cancelTimer(name: "pasta").problem(in: context) == "No timers are running.")
        let running = Self.context(timers: [.init(label: "Pasta", secondsLeft: 60)])
        #expect(AssistantAction.timeLeft.problem(in: running) == nil)
        #expect(AssistantAction.setTimer(minutes: 2000, name: nil).problem(in: context) != nil)
    }

    // MARK: Rails

    @Test func noneAndEmptySayNothing() {
        let context = Self.context()
        #expect(AssistantRails.check("none", context: context) == nil)
        #expect(AssistantRails.check(" None. ", context: context) == nil)
        #expect(AssistantRails.check("", context: context) == nil)
    }

    @Test func anOrdinaryAnswerPasses() {
        let reply = "Use olive oil instead of butter, about the same amount."
        #expect(AssistantRails.check(reply, context: Self.context()) == reply)
    }

    @Test func aTimeOrTemperatureFromTheRecipeOrTheTablePasses() {
        let context = Self.context()
        for reply in ["Boil the pasta for 9 minutes.", "Cook chicken to 165 degrees.", "Let it rest 3 minutes.",
                      "Pork needs 145°F.", "About 1 minute for the garlic."] {
            #expect(AssistantRails.check(reply, context: context) == reply, "\(reply)")
        }
    }

    @Test func aTimeOrTemperatureNotInTheRecipeIsReplaced() {
        let context = Self.context()
        for reply in ["Boil it for 12 minutes.", "Heat the oven to 350°F.", "Fry at 375 degrees.",
                      "Give it twenty minutes.", "Simmer 2 to 3 hours.", "About 30 seconds.", "Heat to 180C."] {
            #expect(AssistantRails.check(reply, context: context) == AssistantRails.unsure, "\(reply)")
        }
    }

    @Test func numbersWithoutATimeOrTemperatureUnitAreLeftAlone() {
        let reply = "Four tablespoons make a quarter cup."
        #expect(AssistantRails.check(reply, context: Self.context()) == reply)
    }

    @Test func runningTimersCountAsKnownTimes() {
        let context = Self.context(timers: [.init(label: "Pasta", secondsLeft: 7 * 60 + 20)])
        #expect(AssistantRails.unsupportedNumbers(in: "About 7 minutes left.", context: context).isEmpty)
        #expect(AssistantRails.unsupportedNumbers(in: "About 8 minutes left.", context: context).isEmpty)
        #expect(AssistantRails.unsupportedNumbers(in: "About 6 minutes left.", context: context) == [6])
    }

    @Test func theAppNeverSaysFoodIsDone() {
        let context = Self.context()
        for reply in ["Your pasta is done.", "The chicken is cooked through.", "It's ready, enjoy!",
                      "Yes, they're done.", "That's fully cooked and safe to eat."] {
            #expect(AssistantRails.check(reply, context: context) == FoodSafety.cannotTell, "\(reply)")
        }
    }

    @Test func sayingWhatToCheckIsAllowed() {
        let context = Self.context()
        for reply in ["It's ready when the pasta is tender but firm.", "The garlic is done once it smells nutty."] {
            #expect(AssistantRails.check(reply, context: context) == reply, "\(reply)")
        }
    }

    @Test func aLongReplyIsCutAtTheSentenceBeforeTheLimit() {
        let first = "Butter browns quickly over medium heat, so keep the pan moving and watch the color closely."
        let second = "If it starts to smell nutty and the foam settles, take it off the heat and add the garlic right away so it does not burn."
        let cut = AssistantRails.check(first + " " + second, context: Self.context())
        #expect(cut == first)
    }

    @Test func aLongSentenceWithNoEndIsCutAtTheLimit() {
        let words = (1...60).map { _ in "stir" }.joined(separator: " ")
        let cut = AssistantRails.cut(words)
        #expect(cut.split(separator: " ").count == AssistantRails.maximumWords)
        #expect(cut.hasSuffix("stir."))
    }

    @Test func aShortReplyIsNotCut() {
        #expect(AssistantRails.cut("Stir it.") == "Stir it.")
    }

    // MARK: Food safety

    @Test func foodSafetyTableHasTheUSDAMinimums() {
        func rule(_ food: String) -> FoodSafety.Rule? { FoodSafety.rules.first { $0.words.contains(food) } }
        #expect(rule("chicken")?.fahrenheit == 165)
        #expect(rule("turkey")?.fahrenheit == 165)
        #expect(rule("ground")?.fahrenheit == 160)
        #expect(rule("steak")?.fahrenheit == 145)
        #expect(rule("steak")?.restMinutes == 3)
        #expect(rule("pork")?.restMinutes == 3)
        #expect(rule("lamb")?.fahrenheit == 145)
        #expect(rule("salmon")?.fahrenheit == 145)
        #expect(rule("salmon")?.restMinutes == nil)
        #expect(rule("leftovers")?.fahrenheit == 165)
        #expect(FoodSafety.temperatures == [145, 160, 165])
    }

    @Test func doneTemperatureQuestionsAreAnsweredFromTheTable() {
        #expect(FoodSafety.answer(to: "what temperature for chicken")
                == "Poultry: 165 degrees Fahrenheit at the thickest part. Check with a thermometer.")
        #expect(FoodSafety.answer(to: "how hot does ground beef need to be")?.contains("160 degrees") == true)
        #expect(FoodSafety.answer(to: "what's a safe temp for pork chops")
                == "Whole cuts of beef, pork and lamb: 145 degrees Fahrenheit at the thickest part, then rest 3 minutes. Check with a thermometer.")
        #expect(FoodSafety.answer(to: "what temperature should salmon be")?.contains("145 degrees") == true)
        #expect(FoodSafety.answer(to: "how hot should I reheat leftovers")?.contains("165 degrees") == true)
        #expect(FoodSafety.answer(to: "is it safe to eat raw chicken")?.contains("165 degrees") == true)
    }

    @Test func doneQuestionsSayWhatToCheck() {
        #expect(FoodSafety.answer(to: "is it done") == FoodSafety.cannotTell)
        #expect(FoodSafety.answer(to: "are the eggs ready") == FoodSafety.cannotTell)
        let chicken = FoodSafety.answer(to: "is the chicken done")
        #expect(chicken?.hasPrefix(FoodSafety.cannotTell) == true)
        #expect(chicken?.contains("165") == true)
        #expect(!FoodSafety.cannotTell.lowercased().contains("is done"))
    }

    @Test func otherQuestionsAreNotTheTables() {
        #expect(FoodSafety.answer(to: "how hot should the oil be") == nil)
        #expect(FoodSafety.answer(to: "what's next") == nil)
        #expect(FoodSafety.answer(to: "what can I use instead of butter") == nil)
        #expect(FoodSafety.answer(to: "how long does the chicken rest") == nil)
    }

    @Test func everyTableLinePassesTheRails() {
        let context = Self.context()
        for rule in FoodSafety.rules {
            let line = FoodSafety.line(for: rule)
            #expect(AssistantRails.check(line, context: context) == line, "\(line)")
        }
    }
}
