import Testing
@testable import PanWatchCore

@Suite("Voice grammar")
struct VoiceGrammarTests {
    private func expect(_ cases: [(String, VoiceCommand)]) {
        for (text, command) in cases {
            #expect(VoiceCommand.parse(text) == command, "\(text)")
        }
    }

    @Test func steps() {
        expect([
            ("go on", .next), ("read the step", .repeatStep),
            ("step three", .goToStep(3)), ("go to step 3", .goToStep(3)), ("skip to step five", .goToStep(5)),
            ("step to", .goToStep(2)), ("go to step twenty one", .goToStep(21)),
            ("where am I", .whereAmI), ("what step", .whereAmI), ("which step is this", .whereAmI),
            ("what do I need", .ingredients),
            ("start over", .startOver), ("from the top", .startOver), ("first step", .startOver),
        ])
    }

    @Test func timers() {
        expect([
            ("set a timer for five minutes", .setTimer(minutes: 5)), ("ten minute timer", .setTimer(minutes: 10)),
            ("five minutes", .setTimer(minutes: 5)), ("set a timer for 12 minutes", .setTimer(minutes: 12)),
            ("5-minute timer", .setTimer(minutes: 5)), ("twenty five minutes", .setTimer(minutes: 25)),
            ("cancel the pasta timer", .cancelNamedTimer("pasta")), ("stop the rice timer", .cancelNamedTimer("rice")),
            ("clear the timer", .cancelTimer), ("cancel my timer", .cancelTimer),
            ("clear it", .clearDone), ("got it", .clearDone),
            ("how long", .timeLeft), ("how much longer", .timeLeft),
        ])
        #expect(VoiceCommand.timer(named: "pasta", matches: "Pasta"))
        #expect(VoiceCommand.timer(named: "five minute", matches: "5 minute"))
        #expect(VoiceCommand.timer(named: "eggs", matches: "Egg"))
        #expect(!VoiceCommand.timer(named: "rice", matches: "Pasta"))
        #expect(!VoiceCommand.timer(named: "", matches: "Pasta"))
    }

    @Test func recipesAndScreens() {
        expect([
            ("recipes", .showRecipes), ("show the recipes", .showRecipes), ("what can I cook", .showRecipes),
            ("make the rice", .makeRecipe("Rice")), ("let's do pasta", .makeRecipe("Garlic Butter Pasta")),
            ("cook the eggs", .makeRecipe("Hard-Boiled Eggs")), ("garlic butter pasta", .makeRecipe("Garlic Butter Pasta")),
            ("make the chicken", .makeRecipe("Pan-Seared Chicken")), ("steamed broccoli", .makeRecipe("Steamed Broccoli")),
            ("lets make oatmeal", .makeRecipe("Oatmeal")),
            ("settings", .settings), ("open settings", .settings),
            ("help", .help), ("what can I say", .help), ("commands", .help),
            ("done", .done), ("close", .done), ("never mind", .done),
            ("show the details", .details(show: true)), ("hide the details", .details(show: false)),
            ("details", .details(show: nil)),
            ("record a practice", .recordPractice(true)), ("start recording", .recordPractice(true)),
            ("stop recording", .recordPractice(false)),
        ])
    }

    @Test func recipeNamesNeedTwoWordsAndNoTalk() {
        let titles = Recipe.all.map(\.title)
        #expect(VoiceCommand.recipeTitle(in: ["make", "rice"], titles: titles) == "Rice")
        #expect(VoiceCommand.recipeTitle(in: ["boiled", "egg"], titles: titles) == "Hard-Boiled Eggs")
        // One word of a name, or a name in a sentence, is talk.
        for words in [["rice"], ["pasta", "looks", "good"], ["i", "love", "chicken", "pasta"], ["garlic", "rice"],
                      ["hard", "boiled", "eggs", "are", "great"], ["can", "we", "make", "rice"], ["make", "it"]] {
            #expect(VoiceCommand.recipeTitle(in: words, titles: titles) == nil, "\(words)")
        }
        for text in ["the pasta looks good", "I love chicken", "pasta", "the rice is done", "that chicken smells great"] {
            if case .makeRecipe = VoiceCommand.parse(text) { Issue.record("\(text)") }
        }
    }

    @Test func camera() {
        expect([
            ("turn off the camera", .camera(on: false)), ("camera off", .camera(on: false)),
            ("stop watching", .camera(on: false)),
            ("turn on the camera", .camera(on: true)), ("camera on", .camera(on: true)),
            ("switch camera", .switchCamera(toFront: nil)), ("use the front camera", .switchCamera(toFront: true)),
            ("use the back camera", .switchCamera(toFront: false)),
            ("watch the pan", .startWatching), ("watch", .startWatching),
        ])
    }

    @Test func drawingThePanByVoice() {
        expect([
            ("draw a new box", .drawPan), ("draw the pan again", .drawPan), ("mark the pan", .drawPan),
            ("yes", .yes), ("bigger", .nudge(.bigger)), ("smaller", .nudge(.smaller)), ("make it bigger", .nudge(.bigger)),
            ("left", .nudge(.left)), ("right", .nudge(.right)), ("up", .nudge(.up)), ("down", .nudge(.down)),
            ("a bit larger", .nudge(.bigger)), ("start watching", .startWatching), ("cancel", .no),
        ])
        #expect(VoiceCommand.parse("all right") != .nudge(.right))
        #expect(VoiceCommand.parse("time left") == .timeLeft)
        #expect(VoiceCommand.parse("turn left at the lights then") == nil)
    }

    @Test func nudgesMoveTheBoxByATenthInsideTheFrame() {
        let box = NormRect.voiceStart
        #expect(abs(box.nudged(.left).x - (box.x - 0.1)) < 1e-9)
        #expect(abs(box.nudged(.right).x - (box.x + 0.1)) < 1e-9)
        #expect(abs(box.nudged(.up).y - (box.y - 0.1)) < 1e-9)
        #expect(abs(box.nudged(.down).y - (box.y + 0.1)) < 1e-9)
        let bigger = box.nudged(.bigger)
        #expect(abs(bigger.width - (box.width + 0.1)) < 1e-9)
        #expect(abs((bigger.x + bigger.width / 2) - (box.x + box.width / 2)) < 1e-9)
        #expect(abs(box.nudged(.smaller).width - (box.width - 0.1)) < 1e-9)
        let corner = NormRect(x: 0, y: 0, width: 0.3, height: 0.3)
        #expect(corner.nudged(.left) == corner)
        #expect(corner.nudged(.up) == corner)
        #expect(NormRect(x: 0, y: 0, width: 1, height: 1).nudged(.bigger).width == 1)
    }

    @Test func voices() {
        expect([
            ("change the voice", .showVoices), ("pick a voice", .showVoices), ("voices", .showVoices),
            ("try Samantha", .tryVoice("samantha")), ("hear Samantha", .tryVoice("samantha")), ("try it", .tryVoice(nil)),
            ("next voice", .nextVoice),
            ("use Samantha", .useVoice(.named("samantha"))), ("use my voice", .useVoice(.mine)),
            ("use this one", .useVoice(.highlighted)),
        ])
    }

    @Test func talking() {
        expect([
            ("be quiet", .quiet), ("mute", .quiet), ("stop talking", .quiet),
            ("talk to me", .talk), ("unmute", .talk), ("speak", .talk),
            ("stop listening", .stopListening), ("pause listening", .stopListening), ("listen later", .stopListening),
        ])
    }

    @Test func sixWordsCountAndTheOldAnswersKeepTheirMeaning() {
        #expect(VoiceCommand.maximumWords == 6)
        #expect(VoiceCommand.parse("okay could you go to the next step") == nil)
        #expect(VoiceCommand.parse("stop") == .no)
        #expect(VoiceCommand.parse("no, use Samantha") == .no)
        #expect(VoiceCommand.parse("stop the timer") == .cancelTimer)
    }

    @Test func sayLinePhrasesFitTheScreen() {
        #expect(AppScreen.sayPhrases(screen: .recipes) == ["make the rice", "let's do pasta", "done"])
        #expect(AppScreen.sayPhrases(screen: .settings, cameraOn: false).first == "turn on the camera")
        #expect(AppScreen.sayPhrases(screen: .voices, voiceName: "Daniel") == ["try Daniel", "use Daniel", "next voice", "done"])
        #expect(AppScreen.sayPhrases(screen: .cook, drawing: true) == ["bigger", "smaller", "start watching", "cancel"])
        #expect(AppScreen.sayPhrases(screen: .cook, offer: true) == ["yes", "no", "not now"])
        #expect(AppScreen.sayPhrases(screen: .cook, needsPan: true) == ["mark the pan", "next step"])
        #expect(AppScreen.sayPhrases(screen: .cook, canStartTimer: true).contains("start the timer"))
        // Every phrase on the Say line does something when said.
        for screen in [AppScreen.cook, .recipes, .settings, .voices, .help] {
            for drawing in [false, true] {
                for phrase in AppScreen.sayPhrases(screen: screen, drawing: drawing) {
                    #expect(VoiceCommand.parse(phrase) != nil, "\(phrase)")
                }
            }
        }
    }

    @Test func modelAnswersCoverTheScreenCommands() {
        #expect(HeardIntent.all.count == VoiceIntent.allCases.count + ScreenIntent.allCases.count)
        #expect(HeardIntent.none.command == nil)
        #expect(HeardIntent.screen(.cameraOff).command == .camera(on: false))
        #expect(HeardIntent.screen(.done).rawValue == "done")
        for intent in ScreenIntent.allCases {
            #expect(IntentContext.instructions.contains("- \(intent.rawValue): \(intent.meaning)"), "\(intent)")
        }
    }
}
