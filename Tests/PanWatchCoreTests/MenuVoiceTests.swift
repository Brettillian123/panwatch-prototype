import Testing
@testable import PanWatchCore

@Suite("Menus by voice")
struct MenuVoiceTests {
    @Test func oneWordPicksADishOnTheRecipeMenu() {
        let picks: [(String, String)] = [
            ("rice", "Rice"), ("eggs", "Hard-Boiled Eggs"), ("egg", "Hard-Boiled Eggs"), ("oatmeal", "Oatmeal"),
            ("chicken", "Pan-Seared Chicken"), ("broccoli", "Steamed Broccoli"), ("pasta", "Garlic Butter Pasta"),
            ("the rice please", "Rice"), ("um, pasta", "Garlic Butter Pasta"), ("garlic", "Garlic Butter Pasta"),
        ]
        for (text, title) in picks {
            #expect(VoiceCommand.parse(text, screen: .recipes) == .makeRecipe(title), "\(text)")
        }
    }

    @Test func elsewhereOneWordOfADishIsTalk() {
        for text in ["rice", "eggs", "oatmeal", "chicken", "broccoli", "pasta"] {
            for screen in [AppScreen.cook, .settings, .voices, .help] {
                if case .makeRecipe = VoiceCommand.parse(text, screen: screen) { Issue.record("\(text) on \(screen)") }
            }
        }
        // Two words still pick a dish everywhere.
        #expect(VoiceCommand.parse("make the rice") == .makeRecipe("Rice"))
        #expect(VoiceCommand.parse("make the rice", screen: .recipes) == .makeRecipe("Rice"))
    }

    @Test func theRecipeMenuStillHearsCommandsAndTalk() {
        #expect(VoiceCommand.parse("done", screen: .recipes) == .done)
        #expect(VoiceCommand.parse("help", screen: .recipes) == .help)
        #expect(VoiceCommand.parse("settings", screen: .recipes) == .settings)
        #expect(VoiceCommand.parse("back", screen: .recipes) == .back)
        // A sentence that mentions a dish is talk, even here.
        for text in ["the pasta looks good", "I love chicken", "rice is done", "no rice"] {
            if case .makeRecipe = VoiceCommand.parse(text, screen: .recipes) { Issue.record("\(text)") }
        }
    }

    @Test func aWordInTwoTitlesOrNoneIsNoDish() {
        #expect(VoiceCommand.dish(word: "salad") == nil)
        #expect(VoiceCommand.dish(word: "rice", titles: ["Rice", "Fried Rice"]) == nil)
        #expect(VoiceCommand.dish(word: "eggs", titles: ["Rice", "Hard-Boiled Eggs"]) == "Hard-Boiled Eggs")
    }

    @Test func everyHelpPhraseWorks() {
        for group in HelpGroup.allCases {
            #expect(!group.phrases.isEmpty, "\(group)")
            for phrase in group.phrases {
                #expect(VoiceCommand.parse(phrase) != nil, "\(phrase)")
            }
        }
    }

    @Test func helpListsTheWholeGrammar() {
        let listed = Set(HelpGroup.allCases.flatMap(\.phrases).compactMap { VoiceCommand.parse($0) }.map(Self.kind))
        let every = ["next", "back", "repeat", "yes", "no", "start timer", "time left", "start watching", "ingredients",
                     "cancel timer", "draw pan", "mark", "go to step", "where am I", "start over", "set timer",
                     "cancel named timer", "clear done", "show recipes", "make recipe", "nudge", "camera",
                     "switch camera", "show voices", "try voice", "next voice", "use voice", "quiet", "talk",
                     "stop listening", "help", "settings", "details", "done", "record practice"]
        for kind in every {
            #expect(listed.contains(kind), "\(kind)")
        }
    }

    @Test func helpPutsThisScreensGroupsFirst() {
        for screen in [AppScreen.cook, .recipes, .settings, .voices, .help] {
            let order = HelpGroup.ordered(for: screen)
            #expect(order.count == HelpGroup.allCases.count && Set(order) == Set(HelpGroup.allCases), "\(screen)")
        }
        #expect(HelpGroup.ordered(for: .cook).first == .steps)
        #expect(HelpGroup.ordered(for: .recipes).first == .recipes)
        #expect(HelpGroup.ordered(for: .settings).first == .camera)
        #expect(HelpGroup.ordered(for: .voices).first == .voice)
    }

    /// The command without its details. Exhaustive, so a new command fails to compile here
    /// until help has a phrase for it.
    private static func kind(_ command: VoiceCommand) -> String {
        switch command {
        case .next: "next"
        case .back: "back"
        case .repeatStep: "repeat"
        case .yes: "yes"
        case .no: "no"
        case .startTimer: "start timer"
        case .timeLeft: "time left"
        case .startWatching: "start watching"
        case .ingredients: "ingredients"
        case .cancelTimer: "cancel timer"
        case .drawPan: "draw pan"
        case .mark: "mark"
        case .goToStep: "go to step"
        case .whereAmI: "where am I"
        case .startOver: "start over"
        case .setTimer: "set timer"
        case .cancelNamedTimer: "cancel named timer"
        case .clearDone: "clear done"
        case .showRecipes: "show recipes"
        case .makeRecipe: "make recipe"
        case .nudge: "nudge"
        case .camera: "camera"
        case .switchCamera: "switch camera"
        case .showVoices: "show voices"
        case .tryVoice: "try voice"
        case .nextVoice: "next voice"
        case .useVoice: "use voice"
        case .quiet: "quiet"
        case .talk: "talk"
        case .stopListening: "stop listening"
        case .help: "help"
        case .settings: "settings"
        case .details: "details"
        case .done: "done"
        case .recordPractice: "record practice"
        }
    }
}
