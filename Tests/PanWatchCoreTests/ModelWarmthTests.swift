import Testing
@testable import PanWatchCore

/// AI prewarm: the model loads once before the first add, and again after the background.
struct ModelWarmthTests {
    @Test func theFirstRequestLoadsAndLaterOnesDoNothing() {
        var warmth = ModelWarmth()
        #expect(warmth.state == .cold)
        let r1 = warmth.request()
        #expect(r1)
        #expect(warmth.state == .warming)
        let r2 = warmth.request()
        #expect(!r2)
        let r3 = warmth.request()
        #expect(!r3)
        #expect(warmth.state == .warming)
    }

    @Test func anAnswerMeansTheModelIsReady() {
        var warmth = ModelWarmth()
        _ = warmth.request()
        warmth.answered()
        #expect(warmth.state == .warm)
        let r4 = warmth.request()
        #expect(!r4)
        #expect(warmth.status(available: true) == "Model ready")
    }

    @Test func comingBackFromTheBackgroundLoadsAgainOnlyIfACookAsked() {
        var idle = ModelWarmth()
        idle.dropped()
        let r5 = idle.returned()
        #expect(!r5)
        #expect(idle.state == .cold)

        var cooking = ModelWarmth()
        _ = cooking.request()
        cooking.answered()
        cooking.dropped()
        #expect(cooking.state == .cold)
        let r6 = cooking.returned()
        #expect(r6)
        #expect(cooking.state == .warming)
        let r7 = cooking.returned()
        #expect(!r7)
    }

    @Test func theStatusSaysWhatTheCookCanCheck() {
        var warmth = ModelWarmth()
        #expect(warmth.status(available: false) == "Model not available on this phone")
        _ = warmth.request()
        #expect(warmth.status(available: true) == "Model loading")
        #expect(warmth.status(available: false) == "Model not available on this phone")
    }
}
