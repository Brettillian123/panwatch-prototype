import Testing
@testable import PanWatchCore

@Suite("Voice intents")
struct VoiceIntentTests {
    @Test func everyIntentButNoneIsTheSameKeywordCommand() {
        for (intent, command) in [
            (VoiceIntent.next, VoiceCommand.next), (.back, .back), (.repeatStep, .repeatStep),
            (.yes, .yes), (.no, .no), (.startTimer, .startTimer), (.timeLeft, .timeLeft),
            (.startWatching, .startWatching), (.ingredients, .ingredients), (.cancelTimer, .cancelTimer),
        ] {
            #expect(intent.command == command, "\(intent)")
        }
        #expect(VoiceIntent.none.command == nil)
        #expect(VoiceIntent.allCases.count == 11)
    }

    @Test func modelAnswersAreReadByName() {
        #expect(VoiceIntent(rawValue: "next") == .next)
        #expect(VoiceIntent(rawValue: "repeatStep") == .repeatStep)
        #expect(VoiceIntent(rawValue: "none") == VoiceIntent.none)
        #expect(VoiceIntent(rawValue: "dance") == nil)
    }

    @Test func onlySentencesAreWorthAskingAbout() {
        #expect(VoiceIntent.worthAsking("I'm done with the butter, what's next?"))
        #expect(!VoiceIntent.worthAsking(""))
        #expect(!VoiceIntent.worthAsking("um, uh"))
        let speech = "and this is where the app sees the butter go in and offers a timer so you never have to touch the phone"
        #expect(!VoiceIntent.worthAsking(speech))
    }

    @Test func instructionsListEveryCommandAndSayNoneUnlessClear() {
        let instructions = IntentContext.instructions
        for intent in VoiceIntent.allCases {
            #expect(instructions.contains("- \(intent.rawValue): \(intent.meaning)"), "\(intent)")
        }
        #expect(instructions.contains("Answer none unless the cook is clearly speaking to the app"))
    }

    @Test func promptCarriesTheStepTheOfferTheTimersAndTheWords() {
        let context = IntentContext(
            step: "Melt the butter in the pan.",
            offer: "Looks like the butter went in. Start a 3 minute timer?",
            timers: [.init(label: "Rice", secondsLeft: 245), .init(label: "Eggs", secondsLeft: 40)]
        )
        #expect(context.prompt(heard: "I'm done with the butter, what's next?") == """
        Current step: Melt the butter in the pan.
        Offer waiting: Looks like the butter went in. Start a 3 minute timer?
        Running timers: Rice, 4 min 5 s left; Eggs, 40 s left
        The cook said: "I'm done with the butter, what's next?"
        """)
    }

    @Test func promptSaysNoneWhenNothingIsWaitingOrRunning() {
        let prompt = IntentContext(step: "Stir.").prompt(heard: "pass me the salt")
        #expect(prompt.contains("Offer waiting: none\n"))
        #expect(prompt.contains("Running timers: none\n"))
    }

    @Test func spokenDurations() {
        #expect(IntentContext.spoken(40) == "40 s")
        #expect(IntentContext.spoken(120) == "2 min")
        #expect(IntentContext.spoken(245) == "4 min 5 s")
        #expect(IntentContext.spoken(-3) == "0 s")
    }

    @Test func anAnswerOnlyAppliesToTheSameStepAndOffer() {
        let asked = IntentContext(step: "Melt the butter.", offer: nil, timers: [.init(label: "Rice", secondsLeft: 300)])
        var now = asked
        now.timers = [.init(label: "Rice", secondsLeft: 298)]
        #expect(asked.stillApplies(to: now))
        now.step = "Add the eggs."
        #expect(!asked.stillApplies(to: now))
        now = asked
        now.offer = "Start a 3 minute timer?"
        #expect(!asked.stillApplies(to: now))
    }
}
