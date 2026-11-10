import Testing
@testable import PanWatchCore

@Suite("Speech policy")
struct SpeechPolicyTests {
    private let quiet = SpeechState(now: 100)
    private let talking = SpeechState(now: 100, isSpeaking: true)
    private let justCut = SpeechState(now: 100, interruptedAt: 99.2)
    private let cutLongAgo = SpeechState(now: 100, interruptedAt: 98)
    private let step = "Step 2. Add the garlic."

    private func act(_ moment: SpeechMoment, _ state: SpeechState, short: String? = nil) -> SpeechAct {
        SpeechPolicy.act(moment, text: step, short: short, state: state)
    }

    // One test per row of the table.

    @Test func launchAndResumeAreSilent() {
        #expect(act(.launch, quiet) == .silent)
        #expect(act(.resume, quiet) == .silent)
    }

    @Test func recipeChosenSpeaksOnlyByVoice() {
        #expect(act(.recipeChosen(by: .voice), quiet, short: "Pasta.") == .speak("Pasta."))
        #expect(act(.recipeChosen(by: .touch), quiet, short: "Pasta.") == .silent)
        #expect(act(.recipeChosen(by: .button), quiet) == .silent)
    }

    @Test func stepByVoiceChimesThenReads() {
        #expect(act(.stepChanged(by: .voice), quiet) == .earconThenSpeak(.acknowledged, step))
        // The cook asked for it, so even right after cutting the app off.
        #expect(act(.stepChanged(by: .voice), justCut) == .earconThenSpeak(.acknowledged, step))
    }

    @Test func stepByTouchOrButtonIsSilent() {
        #expect(act(.stepChanged(by: .touch), quiet) == .silent)
        #expect(act(.stepChanged(by: .button), quiet) == .silent)
    }

    @Test func timerCallOutChimesAndSpeaksUnlessJustCutOff() {
        #expect(act(.stepChanged(by: .timerCallOut), quiet) == .earconThenSpeak(.timerDone, step))
        #expect(act(.stepChanged(by: .timerCallOut), talking) == .earconThenSpeak(.timerDone, step))
        #expect(act(.stepChanged(by: .timerCallOut), justCut) == .earcon(.timerDone))
        #expect(act(.stepChanged(by: .timerCallOut), cutLongAgo) == .earconThenSpeak(.timerDone, step))
    }

    @Test func offersAreSaidOnceNeverOverTheCook() {
        #expect(act(.offer, quiet) == .speak(step))
        #expect(act(.offer, justCut) == .silent)
        #expect(act(.offer, talking) == .silent)
        #expect(act(.guidance, quiet) == .speak(step))
        #expect(act(.guidance, justCut) == .silent)
    }

    @Test func timerDoneAlwaysChimes() {
        #expect(act(.timerDone, quiet) == .earconThenSpeak(.timerDone, step))
        #expect(act(.timerDone, talking) == .earconThenSpeak(.timerDone, step))
        #expect(act(.timerDone, justCut) == .earcon(.timerDone))
    }

    @Test func answersAreSpoken() {
        #expect(act(.answer, quiet) == .speak(step))
        #expect(act(.answer, justCut) == .speak(step))
    }

    @Test func errorsOnlyWhenAsked() {
        #expect(act(.error(asked: true), quiet) == .speak(step))
        #expect(act(.error(asked: false), quiet) == .silent)
    }

    @Test func confirmationsAreEarconsWhenTheScreenShowsIt() {
        #expect(act(.confirmation(visible: true), quiet) == .earcon(.acknowledged))
        #expect(act(.confirmation(visible: false), quiet) == .speak(step))
    }

    @Test func notUnderstoodIsASound() {
        #expect(act(.notUnderstood, quiet) == .earcon(.notUnderstood))
    }

    // The interruption rule.

    @Test func cooldownLastsOneAndAHalfSeconds() {
        #expect(SpeechState(now: 10, interruptedAt: 9).inCooldown)
        #expect(SpeechState(now: 10.49, interruptedAt: 9).inCooldown)
        #expect(!SpeechState(now: 10.5, interruptedAt: 9).inCooldown)
        #expect(!SpeechState(now: 10).inCooldown)
    }

    @Test func nothingUnaskedInTheCooldown() {
        let unasked: [SpeechMoment] = [.launch, .resume, .offer, .guidance, .stepChanged(by: .touch), .error(asked: false)]
        for moment in unasked {
            #expect(act(moment, justCut) == .silent, "\(moment)")
        }
        // Timers still chime, without words.
        #expect(act(.timerDone, justCut) == .earcon(.timerDone))
        #expect(act(.stepChanged(by: .timerCallOut), justCut) == .earcon(.timerDone))
    }

    // Completeness.

    @Test func completeCommandsEndQuickly() {
        for text in ["next", "next step please", "go back", "read it", "set a timer for ten minutes"] {
            #expect(TurnTaking.isComplete(text), "\(text)")
            #expect(TurnTaking.pause(after: text) == TurnTaking.completePause)
        }
    }

    @Test func incompleteOnesWait() {
        for text in ["how long do I", "how much", "what can I use for the", "set a timer for", "", "honey can you"] {
            #expect(!TurnTaking.isComplete(text), "\(text)")
            #expect(TurnTaking.pause(after: text) == TurnTaking.incompletePause)
        }
    }

    // Backchannels.

    @Test func backchannelsDoNotStopTheApp() {
        for words in [["mm"], ["uh", "huh"], ["okay"], ["yeah"], ["mm", "hm"], ["mhm"], ["right"]] {
            #expect(TurnTaking.isBackchannel(words), "\(words)")
        }
    }

    @Test func realWordsDo() {
        for words in [["next"], ["stop"], ["wait"], ["okay", "next"], ["yeah", "yeah", "yeah"], [], ["go", "back"]] {
            #expect(!TurnTaking.isBackchannel(words), "\(words)")
        }
    }

    @Test func followUpWindow() {
        #expect(TurnTaking.asksModel(wordCount: 2, secondsSinceReply: nil))
        #expect(TurnTaking.asksModel(wordCount: 5, secondsSinceReply: 3))
        #expect(!TurnTaking.asksModel(wordCount: 5, secondsSinceReply: 8))
        #expect(!TurnTaking.asksModel(wordCount: 5, secondsSinceReply: nil))
    }

    // Earcons.

    @Test func earconsAreShortQuietAndDistinct() {
        let rate = 24000.0
        var lengths: Set<Int> = []
        for earcon in Earcon.allCases {
            let samples = earcon.samples(sampleRate: rate)
            #expect(!samples.isEmpty)
            #expect(Double(samples.count) / rate < 0.6)
            #expect(samples.allSatisfy { abs($0) <= Earcon.amplitude })
            #expect(abs(samples.first!) < 0.01 && abs(samples.last!) < 0.05)
            lengths.insert(samples.count)
        }
        #expect(lengths.count == Earcon.allCases.count)
    }

    // "Read it".

    @Test func readItRepeatsTheStep() {
        for text in ["read it", "read the step", "say that again", "read that", "repeat"] {
            #expect(VoiceCommand.parse(text) == .repeatStep, "\(text)")
        }
        #expect(VoiceCommand.parse("read the ingredients") == .ingredients)
    }
}
