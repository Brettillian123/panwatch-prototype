import Testing
@testable import PanWatchCore

/// Natural phrasings a cook says during the five-minute demo, each on the screen it applies to.
@Suite("Voice coverage")
struct VoiceCoverageTests {
    @Test func demoPhrasings() {
        let cases: [(String, AppScreen, VoiceCommand)] = [
            ("next", .cook, .next), ("okay next step", .cook, .next), ("um, go on", .cook, .next),
            ("next step please", .cook, .next),
            ("back", .cook, .back), ("go back", .cook, .back), ("previous step please", .cook, .back),
            ("repeat", .cook, .repeatStep), ("say that again", .cook, .repeatStep), ("read the step", .cook, .repeatStep),
            ("um, repeat that please", .cook, .repeatStep),
            ("start the timer", .cook, .startTimer), ("timer", .cook, .startTimer), ("okay start the timer please", .cook, .startTimer),
            ("yes", .cook, .yes), ("sure", .cook, .yes), ("yeah okay", .cook, .yes), ("start it", .cook, .yes),
            ("no", .cook, .no), ("not now", .cook, .no), ("no thanks", .cook, .no), ("cancel", .cook, .no),
            ("restart", .cook, .startOver), ("restart the recipe", .cook, .startOver), ("start over", .cook, .startOver),
            ("from the top", .cook, .startOver),
            ("recipes", .cook, .showRecipes), ("show the recipes", .cook, .showRecipes), ("what can I cook", .cook, .showRecipes),
            ("make the rice", .recipes, .makeRecipe("Rice")), ("rice", .recipes, .makeRecipe("Rice")),
            ("let's do pasta", .recipes, .makeRecipe("Garlic Butter Pasta")), ("make the rice", .cook, .makeRecipe("Rice")),
            ("cook the eggs please", .recipes, .makeRecipe("Hard-Boiled Eggs")),
            ("draw a new box", .cook, .drawPan), ("mark the pan", .cook, .drawPan), ("draw the pan again", .cook, .drawPan),
            ("mark the pan", .settings, .drawPan),
            ("start watching", .cook, .startWatching), ("watch the pan", .cook, .startWatching), ("okay watch", .cook, .startWatching),
            ("ingredients", .cook, .ingredients), ("what do I need", .cook, .ingredients), ("read the ingredients please", .cook, .ingredients),
            ("how long", .cook, .timeLeft), ("time left", .cook, .timeLeft), ("how much longer", .cook, .timeLeft),
            ("um how long is left", .cook, .timeLeft),
            ("cancel the timer", .cook, .cancelTimer), ("stop the timer", .cook, .cancelTimer), ("clear the timer please", .cook, .cancelTimer),
            ("what can I say", .cook, .help), ("help", .cook, .help), ("commands", .cook, .help), ("um, help me", .cook, .help),
            ("done", .recipes, .done), ("close", .settings, .done), ("never mind", .help, .done),
        ]
        for (text, screen, command) in cases {
            #expect(VoiceCommand.parse(text, screen: screen, book: DemoBook.voice) == command, "\(text) on \(screen)")
        }
    }

    @Test func conversationDoesNothing() {
        let talk = [
            "so then I put the pasta in the water",
            "next time I'll use less salt",
            "can you believe the game last night",
            "I think the rice is almost ready to go",
            "do you want me to go back to the slides after this",
            "let me know when you're done with the timer thing",
            "we should probably start the chicken after the broccoli",
            "my mom always said to repeat the recipe twice",
            "I'm not sure how long this usually takes to cook",
            "hey can you help me find the garlic in the fridge",
        ]
        for text in talk {
            #expect(VoiceCommand.parse(text) == nil, "(text)")
            #expect(VoiceCommand.parse(text, screen: .recipes) == nil, "(text)")
        }
    }
}
