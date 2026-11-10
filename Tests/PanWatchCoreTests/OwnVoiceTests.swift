import Foundation
import Testing
@testable import PanWatchCore

struct OwnVoiceTests {
    @Test func nothingRecordsBeforeConsent() {
        var flow = OwnVoiceFlow()
        #expect(flow.step == .consent)
        let r1 = flow.startRecording()
        #expect(r1 == nil)
        #expect(!flow.canFinish)
        let r2 = flow.finish(take: 0)
        #expect(!r2)
        let r3 = flow.finish(take: 1)
        #expect(!r3)
        flow.tryAgain()
        #expect(flow.step == .consent)
    }

    @Test func consentThenALongTakeCanFinish() throws {
        var flow = OwnVoiceFlow()
        flow.acceptConsent()
        #expect(flow.step == .ready && flow.consented)
        let startedtake = flow.startRecording()
        let take = try #require(startedtake)
        #expect(flow.step == .recording)
        let r4 = flow.startRecording()
        #expect(r4 == nil)
        flow.stopRecording(take: take, seconds: 15)
        #expect(flow.step == .recorded && flow.canFinish)
        let r5 = flow.finish(take: take)
        #expect(r5)
        #expect(flow.step == .done)
    }

    @Test func aShortTakeAsksAgain() throws {
        var flow = OwnVoiceFlow()
        flow.acceptConsent()
        let startedtake = flow.startRecording()
        let take = try #require(startedtake)
        flow.stopRecording(take: take, seconds: OwnVoice.minSeconds - 1)
        #expect(flow.step == .ready && flow.problem == .tooShort)
        let kept = flow.finish(take: take)
        #expect(!flow.canFinish && !kept)
    }

    @Test func onlyTheLatestTakeOfThisFlowIsKept() throws {
        var flow = OwnVoiceFlow()
        flow.acceptConsent()
        let startedfirst = flow.startRecording()
        let first = try #require(startedfirst)
        flow.stopRecording(take: first, seconds: 12)
        let startedsecond = flow.startRecording()
        let second = try #require(startedsecond)
        // A stale take number can't stop or keep the running take.
        flow.stopRecording(take: first, seconds: 12)
        #expect(flow.step == .recording)
        flow.stopRecording(take: second, seconds: 14)
        let r6 = flow.finish(take: first)
        #expect(!r6)
        let r7 = flow.finish(take: second + 1)
        #expect(!r7)
        let r8 = flow.finish(take: second)
        #expect(r8)
    }

    @Test func tryAgainDropsTheTake() throws {
        var flow = OwnVoiceFlow()
        flow.acceptConsent()
        let startedtake = flow.startRecording()
        let take = try #require(startedtake)
        flow.stopRecording(take: take, seconds: 15)
        flow.tryAgain()
        #expect(flow.step == .ready && !flow.canFinish && flow.seconds == 0)
    }

    @Test func myVoicePrefersTheRecordedOne() {
        #expect(OwnVoice.mine(recorded: true, personalID: "personal.1") == OwnVoice.id)
        #expect(OwnVoice.mine(recorded: false, personalID: "personal.1") == "personal.1")
        #expect(OwnVoice.mine(recorded: false, personalID: nil) == nil)
        #expect(OwnVoice.isOwn(OwnVoice.id) && !OwnVoice.isOwn("kokoro:af_heart") && !OwnVoice.isOwn(nil))
    }

    @Test func fallbackIsTheVoicePickedBefore() {
        #expect(OwnVoice.fallback(previous: "kokoro:af_heart", current: nil) == "kokoro:af_heart")
        #expect(OwnVoice.fallback(previous: OwnVoice.id, current: "kokoro:bm_george") == "kokoro:bm_george")
        #expect(OwnVoice.fallback(previous: nil, current: nil) == nil)
    }

    @Test func namesAreCleaned() {
        #expect(OwnVoice.cleanName("  Dad  ") == "Dad")
        #expect(OwnVoice.cleanName("   ") == OwnVoice.defaultName)
        #expect(OwnVoice.cleanName(String(repeating: "a", count: 40)).count == OwnVoice.maxNameLength)
    }

    @Test func meterSpansQuietToLoud() {
        #expect(OwnVoice.meter(rms: 0) == 0)
        #expect(OwnVoice.meter(rms: 0.001) == 0)
        #expect(OwnVoice.meter(rms: 1) == 1)
        let mid = OwnVoice.meter(rms: 0.01)
        #expect(mid > 0.2 && mid < 0.3)
    }

    @Test func cloneClipTrimsSilenceAndCapsAtTenSeconds() {
        let rate = OwnVoice.sampleRate
        let silence = [Float](repeating: 0, count: Int(rate))
        let tone = (0..<Int(rate * 3)).map { Float(sin(Double($0) * 0.05) * 0.3) }
        let clip = OwnVoice.cloneClip(silence + tone + silence, sampleRate: rate)
        #expect(abs(clip.count - tone.count) <= Int(rate * 0.02))
        #expect(OwnVoice.cloneClip(silence, sampleRate: rate).isEmpty)
        #expect(OwnVoice.cloneClip([], sampleRate: rate).isEmpty)
        let long = (0..<Int(rate * 15)).map { Float(sin(Double($0) * 0.05) * 0.3) }
        #expect(OwnVoice.cloneClip(long, sampleRate: rate).count == Int(rate * OwnVoice.cloneSeconds))
    }

    @Test func creditsNameEveryVoiceModelAndItsLicense() {
        let byTitle = Dictionary(uniqueKeysWithValues: Credits.notices.map { ($0.title, $0.text) })
        let pocket = byTitle["Pocket TTS"] ?? ""
        #expect(pocket.contains("Kyutai") && pocket.contains("CC BY 4.0"))
        #expect(pocket.contains("creativecommons.org/licenses/by/4.0") && pocket.contains("FluidInference"))
        #expect(byTitle["Kokoro"]?.contains("Apache License 2.0") == true)
        #expect(byTitle["FluidAudio"]?.contains("Apache License 2.0") == true)
    }

    @Test func scriptAndConsentAreAsWritten() {
        #expect(OwnVoice.consentLine == "Record only your own voice. It stays on this phone.")
        let words = OwnVoice.script.split(whereSeparator: \.isWhitespace).count
        // About 15 seconds at an easy reading pace.
        #expect(words >= 35 && words <= 50)
        #expect(OwnVoice.minSeconds < OwnVoice.maxSeconds && OwnVoice.cloneSeconds <= OwnVoice.maxSeconds)
    }
}
