import Testing
@testable import PanWatchCore

@Suite("Spoken answers")
struct SpokenAnswerTests {
    @Test func yesWordsStartTheTimer() {
        for text in ["Yes", "yeah", "Sure", "OK", "yes please", "Start the timer"] {
            #expect(SpokenAnswer.parse(text) == .yes, "\(text)")
        }
    }

    @Test func noWordsDismissTheOffer() {
        for text in ["No", "nope", "Not now", "cancel that", "no, don't start it"] {
            #expect(SpokenAnswer.parse(text) == .no, "\(text)")
        }
    }

    @Test func anythingElseIsIgnored() {
        for text in ["", "hmm", "the pasta looks good", "nothing", "notice"] {
            #expect(SpokenAnswer.parse(text) == nil, "\(text)")
        }
    }

    @Test func smallAdditionsAskForLessChange() {
        let garlic = Recipe.garlicButterPasta.steps.first { $0.watch?.ingredient == "garlic" }
        let pasta = Recipe.garlicButterPasta.steps.first { $0.watch?.ingredient == "pasta" }
        #expect(garlic?.watch?.minimumChange == 0)
        #expect(pasta?.watch?.minimumChange == 0)
    }
}
