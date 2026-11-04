import Testing
@testable import PanWatchCore

@Suite("Voice commands")
struct VoiceCommandTests {
    @Test func stepCommands() {
        for (text, command) in [
            ("Next", VoiceCommand.next), ("next step", .next), ("Continue", .next),
            ("Go back", .back), ("back", .back), ("previous step", .back),
            ("Repeat", .repeatStep), ("say that again", .repeatStep),
            ("Start the timer", .startTimer), ("start timer", .startTimer), ("Start a timer please", .startTimer),
            ("How much time is left", .timeLeft), ("time left", .timeLeft), ("how long", .timeLeft),
            ("Start watching", .startWatching),
        ] {
            #expect(VoiceCommand.parse(text) == command, "\(text)")
        }
    }

    @Test func answersToTheOffer() {
        for text in ["Yes", "yeah", "Sure", "OK", "yes please", "start", "do it"] {
            #expect(VoiceCommand.parse(text) == .yes, "\(text)")
        }
        for text in ["No", "nope", "Not now", "cancel that", "no, don't start it", "stop"] {
            #expect(VoiceCommand.parse(text) == .no, "\(text)")
        }
    }

    @Test func ingredientsAndCancellingATimer() {
        for text in ["ingredients", "what are the ingredients", "read the ingredients"] {
            #expect(VoiceCommand.parse(text) == .ingredients, "\(text)")
        }
        for text in ["cancel the timer", "stop the timer", "cancel timer"] {
            #expect(VoiceCommand.parse(text) == .cancelTimer, "\(text)")
        }
        // The old answers keep their meaning.
        for text in ["cancel", "cancel that", "stop", "no", "no ingredients"] {
            #expect(VoiceCommand.parse(text) == .no, "\(text)")
        }
        #expect(VoiceCommand.parse("start the timer") == .startTimer)
    }

    @Test func conversationIsIgnored() {
        for text in [
            "", "hmm", "the pasta looks good", "nothing", "notice",
            "and then I go back to the slides",
            "so next I will show you the timer",
            "yes that is exactly what it does here",
        ] {
            #expect(VoiceCommand.parse(text) == nil, "\(text)")
        }
    }

    @Test func fillerWordsDoNotCount() {
        for (text, command) in [
            ("okay next step please", VoiceCommand.next), ("um go back", .back),
            ("please go to the next step now", .next), ("um uh okay go to the next step please", .next),
            ("uh, repeat that please", .repeatStep), ("hey, start the timer now please", .startTimer),
            ("okay", .yes), ("okay please", .yes), ("start it now", .yes), ("not now", .no), ("um, not now", .no),
        ] {
            #expect(VoiceCommand.parse(text) == command, "\(text)")
        }
        #expect(VoiceCommand.words(in: "Um, next step please") == ["next", "step"])
    }

    @Test func fillerAloneOrInASentenceIsIgnored() {
        for text in ["um", "hey", "now", "please", "uh the", "um so now I am going to stir the pasta please"] {
            #expect(VoiceCommand.parse(text) == nil, "\(text)")
        }
        #expect(VoiceCommand.words(in: "um so now I am going to stir the pasta please").count == 7)
    }

    @Test func smallAdditionsAskForLessChange() {
        let garlic = Recipe.garlicButterPasta.steps.first { $0.watch?.ingredient == "garlic" }
        let pasta = Recipe.garlicButterPasta.steps.first { $0.watch?.ingredient == "pasta" }
        #expect(garlic?.watch?.minimumChange == 0)
        #expect(pasta?.watch?.minimumChange == 0.02)
        #expect(pasta?.watch?.countsRelease == true)
        #expect(garlic?.watch?.countsRelease == false)
    }
}
