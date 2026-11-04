import Testing
@testable import PanWatchCore

@Suite("Barge-in")
struct BargeInTests {
    private let step = "Step two. Add the garlic and stir until it smells toasty."

    @Test func echoOfOwnVoiceDoesNotCount() {
        #expect(SelfEcho.newWords(in: "add the garlic", spoken: step).isEmpty)
        #expect(SelfEcho.newWords(in: "Step two", spoken: step).isEmpty)
        #expect(SelfEcho.newWords(in: "", spoken: step).isEmpty)
    }

    @Test func cooksOwnWordCounts() {
        #expect(SelfEcho.newWords(in: "next", spoken: step) == ["next"])
        // "step" was in the step being read, so only "next" counts; that's enough.
        #expect(SelfEcho.newWords(in: "add the garlic next step", spoken: step) == ["next"])
        #expect(SelfEcho.newWords(in: "repeat", spoken: nil) == ["repeat"])
    }

    @Test func stripLeavesTheCommand() {
        #expect(SelfEcho.strip("Step two add next please", spoken: step) == "next please")
        #expect(SelfEcho.strip("start the timer", spoken: step) == "start timer")
        #expect(VoiceCommand.parse(SelfEcho.strip("Add the garlic and go back", spoken: step)) == .back)
    }

    /// The times at which `readings` (level, seconds) start speech.
    private func starts(_ detector: inout SpeechDetector, _ readings: [(Double, Double)]) -> [Double] {
        readings.compactMap { detector.feed(level: $0.0, at: $0.1) ? $0.1 : nil }
    }

    @Test func detectorNeedsSustainedLevel() {
        var detector = SpeechDetector()
        // A pop shorter than the hold doesn't start speech; loud without a break for the
        // hold does, once.
        let pops = starts(&detector, [(0.1, 0.0), (0.1, 0.1), (0.0, 0.2), (0.1, 0.3), (0.1, 0.5), (0.0, 0.6)])
        #expect(pops.isEmpty)
        #expect(!detector.isSpeech)
        let sustained = starts(&detector, [(0.1, 1.0), (0.1, 1.1), (0.1, 1.25), (0.1, 1.3)])
        #expect(sustained == [1.25])
        #expect(detector.isSpeech)
    }

    @Test func detectorReleasesWithHysteresis() {
        var detector = SpeechDetector()
        #expect(starts(&detector, [(0.1, 0.0), (0.1, 0.25)]) == [0.25])
        // A dip between words, above half the threshold, keeps speech going.
        #expect(starts(&detector, [(0.015, 0.5), (0.015, 1.5)]).isEmpty)
        #expect(detector.isSpeech)
        // Quiet for the release ends it; the next sustained sound starts it again.
        #expect(starts(&detector, [(0.001, 2.0), (0.001, 2.4)]).isEmpty)
        #expect(detector.isSpeech)
        #expect(starts(&detector, [(0.001, 2.5)]).isEmpty)
        #expect(!detector.isSpeech)
        #expect(starts(&detector, [(0.1, 3.0), (0.1, 3.25)]) == [3.25])
    }
}
