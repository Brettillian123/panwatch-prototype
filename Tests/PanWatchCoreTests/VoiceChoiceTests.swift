import Testing
@testable import PanWatchCore

struct VoiceChoiceTests {
    let hannah = "kokoro:af_heart"
    let george = "kokoro:bm_george"
    let samantha = "com.apple.voice.premium.en-US.Samantha"

    @Test func everyCatalogueVoiceHasANameAccentCharacterAndPreview() {
        for voice in VoiceCatalog.voices {
            #expect(!voice.name.isEmpty && voice.name.first?.isUppercase == true, "\(voice.pack)")
            #expect(VoiceAccent.allCases.contains(voice.accent))
            #expect(VoiceCatalog.characters[voice.pack]?.split(separator: " ").count == 2, "\(voice.pack)")
            #expect(VoiceCatalog.previewFile(pack: voice.pack) == "\(voice.pack).m4a")
        }
        #expect(Set(VoiceCatalog.voices.map(\.name)).count == VoiceCatalog.voices.count)
        #expect(Set(VoiceCatalog.voices.map(\.pack)).count == VoiceCatalog.voices.count)
        // A mix has no recorded preview: it is spoken live.
        #expect(VoiceCatalog.previewFile(pack: VoiceCatalog.bellaAndSarah.pack) == nil)
        #expect(VoiceCatalog.previewFile(pack: "af_mix3") == nil)
    }

    @Test func theTenFirstNamesStay() {
        let names = Set(VoiceCatalog.voices.map(\.name))
        for name in ["Hannah", "Bella", "Nicole", "Sarah", "Kora", "Michael", "Finn", "Emma", "George", "Felix"] {
            #expect(names.contains(name), "\(name)")
        }
    }

    @Test func thePreviewLineIsOneShortSentence() {
        #expect(VoiceCatalog.sentences(in: VoiceCatalog.previewLine).count == 1)
        #expect(VoiceCatalog.previewLine.split(separator: " ").count <= 10)
    }

    @Test func aVoiceOnThePhoneIsUsedAtOnce() {
        var choice = VoiceChoice(settled: samantha)
        choice.choose(hannah, readyNow: true)
        #expect(choice.settled == hannah)
        #expect(choice.wanted == nil)
        #expect(choice.marked == hannah)
        #expect(!choice.isPending(hannah))
    }

    @Test func aVoiceNotHereYetIsMarkedWhileTheOldOneSpeaks() {
        var choice = VoiceChoice(settled: samantha)
        choice.choose(hannah, readyNow: false)
        #expect(choice.settled == samantha)
        #expect(choice.marked == hannah)
        #expect(choice.isPending(hannah))
    }

    @Test func itTakesOverWhenReady() {
        var choice = VoiceChoice(settled: samantha)
        choice.choose(hannah, readyNow: false)
        let other = choice.ready(george)
        #expect(!other)
        #expect(choice.settled == samantha)
        let took = choice.ready(hannah)
        #expect(took)
        #expect(choice.settled == hannah)
        #expect(choice.wanted == nil)
        #expect(!choice.isPending(hannah))
    }

    @Test func theLastPickWins() {
        var choice = VoiceChoice(settled: nil)
        choice.choose(hannah, readyNow: false)
        choice.choose(george, readyNow: false)
        #expect(choice.marked == george)
        #expect(!choice.isPending(hannah))
        choice.allReady()
        #expect(choice.settled == george)
    }

    @Test func pickingAVoiceThatIsHereDropsTheWaitingOne() {
        var choice = VoiceChoice(settled: nil)
        choice.choose(hannah, readyNow: false)
        choice.choose(samantha, readyNow: true)
        #expect(choice.settled == samantha)
        #expect(choice.wanted == nil)
        let late = choice.ready(hannah)
        #expect(!late)
        #expect(choice.settled == samantha)
    }

    @Test func aFailedFetchGoesQuietlyBackAndRetries() {
        var choice = VoiceChoice(settled: samantha)
        choice.choose(hannah, readyNow: false)
        choice.failed(.offline)
        #expect(choice.marked == samantha)
        #expect(!choice.isPending(hannah))
        #expect(choice.problem?.caption == "Connect to Wi-Fi to use this voice.")
        let again = choice.retry()
        #expect(again == hannah)
        #expect(choice.isPending(hannah))
        #expect(choice.problem == nil)
        let twice = choice.retry()
        #expect(twice == nil)
    }

    @Test func aFailureWithNothingWantedChangesNothing() {
        var choice = VoiceChoice(settled: samantha)
        choice.failed(.noSpace)
        #expect(choice.problem == nil)
        let again = choice.retry()
        #expect(again == nil)
        #expect(choice.marked == samantha)
    }

    @Test func aFullPhoneSaysSo() {
        #expect(VoiceChoice.Problem.noSpace.caption == "Free up some space to use this voice.")
        #expect(VoiceFetchRule.problem(domain: "NSCocoaErrorDomain", code: 640) == .noSpace)
        #expect(VoiceFetchRule.problem(domain: "NSPOSIXErrorDomain", code: 28) == .noSpace)
        #expect(VoiceFetchRule.problem(domain: "NSURLErrorDomain", code: -1009) == .offline)
        #expect(VoiceFetchRule.hasRoom(availableBytes: 2_000_000_000))
        #expect(!VoiceFetchRule.hasRoom(availableBytes: 50_000_000))
        #expect(VoiceFetchRule.hasRoom(availableBytes: nil))
    }

    @Test func aWaitingVoiceSurvivesARelaunch() {
        let choice = VoiceChoice(settled: samantha, wanted: hannah)
        #expect(choice.isPending(hannah))
        #expect(choice.settled == samantha)
        #expect(VoiceChoice(settled: hannah, wanted: hannah).wanted == nil)
    }

    @Test func theNetworkRule() {
        #expect(VoiceNetwork.from(satisfied: true, expensive: false, constrained: false) == .wifi)
        #expect(VoiceNetwork.from(satisfied: true, expensive: true, constrained: false) == .metered)
        #expect(VoiceNetwork.from(satisfied: true, expensive: false, constrained: true) == .metered)
        #expect(VoiceNetwork.from(satisfied: false, expensive: false, constrained: false) == .offline)
        // On its own: Wi-Fi only.
        #expect(VoiceFetchRule.step(network: .wifi, cookPicked: false, allowedMetered: false) == .start)
        #expect(VoiceFetchRule.step(network: .metered, cookPicked: false, allowedMetered: false) == .wait)
        #expect(VoiceFetchRule.step(network: .offline, cookPicked: false, allowedMetered: false) == .wait)
        // The cook picked a voice: ask on cellular, once; "Get them now" starts it.
        #expect(VoiceFetchRule.step(network: .wifi, cookPicked: true, allowedMetered: false) == .start)
        #expect(VoiceFetchRule.step(network: .metered, cookPicked: true, allowedMetered: false) == .ask)
        #expect(VoiceFetchRule.step(network: .metered, cookPicked: true, allowedMetered: true) == .start)
        #expect(VoiceFetchRule.step(network: .offline, cookPicked: true, allowedMetered: true) == .wait)
    }
}
