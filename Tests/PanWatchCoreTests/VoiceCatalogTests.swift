import Testing
@testable import PanWatchCore

struct VoiceCatalogTests {
    @Test func tenVoicesPlusTheMix() {
        #expect(VoiceCatalog.voices.count == 10)
        let packs = VoiceCatalog.voices.map(\.pack)
        #expect(packs == [
            "af_heart", "af_bella", "af_nicole", "af_sarah", "af_kore",
            "am_michael", "am_fenrir", "bf_emma", "bm_george", "bm_fable",
        ])
        #expect(Set(VoiceCatalog.voices.map(\.name)).count == 10)
        #expect(VoiceCatalog.defaultVoice.pack == "af_heart")
        let mix = VoiceCatalog.bellaAndSarah
        #expect(VoiceCatalog.isValidPack(mix.pack))
        #expect(mix.voice.accent == .american && mix.voice.gender == .female)
        #expect(mix.voice.detail == "Mix of Bella and Sarah")
    }

    @Test func accentAndGenderFollowThePackName() {
        for voice in VoiceCatalog.voices {
            #expect(voice.accent == (voice.pack.hasPrefix("a") ? .american : .british), "\(voice.pack)")
            #expect(voice.gender == (voice.pack.dropFirst().hasPrefix("f") ? .female : .male), "\(voice.pack)")
            #expect(!voice.detail.isEmpty && !voice.detail.contains("—"))
            // The model's names never reach the screen.
            #expect(!voice.name.contains("_"))
        }
    }

    @Test func idsRoundTripAndNeverLookLikeApple() {
        for voice in VoiceCatalog.voices {
            #expect(VoiceCatalog.isNatural(voice.id))
            #expect(VoiceCatalog.pack(fromID: voice.id) == voice.pack)
        }
        #expect(!VoiceCatalog.isNatural("com.apple.voice.premium.en-US.Zoe"))
        #expect(VoiceCatalog.pack(fromID: "com.apple.voice.premium.en-US.Zoe") == nil)
        #expect(VoiceCatalog.pack(fromID: nil) == nil)
        #expect(VoiceCatalog.pack(fromID: "kokoro:../etc") == nil)
        #expect(VoiceCatalog.pack(fromID: "kokoro:zf_001") == nil)
        #expect(VoiceCatalog.pack(fromID: "kokoro:af_Heart") == nil)
    }

    @Test func menuOrderGroupsByAccent() {
        let blend = VoiceBlend(name: "Sunday", first: "bm_george", second: "af_bella", balance: 0.7, pack: "bm_mix1")
        let list = VoiceCatalog.menuOrder(blends: [blend])
        #expect(list.count == 11)
        #expect(list.prefix(7).allSatisfy { $0.accent == .american })
        #expect(list[7..<10].allSatisfy { $0.accent == .british })
        #expect(list.last?.name == "Sunday")
        #expect(list.last?.accent == .british && list.last?.gender == .male)
    }

    @Test func nextOfAKindWraps() {
        let list = VoiceCatalog.menuOrder(blends: [])
        let british = VoiceCatalog.next(after: nil, accent: .british, gender: nil, in: list)
        #expect(british?.pack == "bf_emma")
        #expect(VoiceCatalog.next(after: british?.id, accent: .british, gender: nil, in: list)?.pack == "bm_george")
        #expect(VoiceCatalog.next(after: "kokoro:bm_fable", accent: .british, gender: nil, in: list)?.pack == "bf_emma")
        #expect(VoiceCatalog.next(after: "kokoro:af_heart", accent: nil, gender: .male, in: list)?.pack == "am_michael")
        #expect(VoiceCatalog.next(after: "kokoro:am_michael", accent: .american, gender: .male, in: list)?.pack == "am_fenrir")
        #expect(VoiceCatalog.next(after: nil, accent: .british, gender: .female, in: []) == nil)
    }

    @Test func blendPackIsLedByTheLargerShare() {
        #expect(VoiceCatalog.blendPack(first: "bm_george", second: "af_bella", balance: 0.6, number: 3) == "bm_mix3")
        #expect(VoiceCatalog.blendPack(first: "bm_george", second: "af_bella", balance: 0.4, number: 3) == "af_mix3")
        #expect(VoiceCatalog.blendPack(first: "zz", second: "af_bella", balance: 0.9, number: 1) == nil)
        #expect(VoiceCatalog.isValidPack(VoiceCatalog.blendPack(first: "af_heart", second: "am_michael", balance: 0.5, number: 12)!))
    }

    @Test func mixIsWeighted() {
        #expect(VoiceCatalog.mix([1, 0], [0, 1], balance: 0.75) == [0.75, 0.25])
        #expect(VoiceCatalog.mix([2, 4], [4, 8], balance: 0.5) == [3, 6])
        #expect(VoiceCatalog.mix([1], [0], balance: 2) == [1])
        #expect(VoiceCatalog.mix([1, 2], [1], balance: 0.5) == nil)
        #expect(VoiceCatalog.mix([], [], balance: 0.5) == nil)
    }

    @Test func speedSteps() {
        #expect(VoiceSpeed.normal.factor == 1)
        #expect(VoiceSpeed.slower.factor < 1 && VoiceSpeed.faster.factor > 1)
        #expect(VoiceSpeed.normal.step(faster: true) == .faster)
        #expect(VoiceSpeed.faster.step(faster: true) == .faster)
        #expect(VoiceSpeed.normal.step(faster: false) == .slower)
        #expect(VoiceSpeed.slower.step(faster: false) == .slower)
    }

    @Test func sentencesStartPlayingEarly() {
        #expect(VoiceCatalog.sentences(in: "Step two. Add the garlic and stir until it smells toasty.")
            == ["Step two.", "Add the garlic and stir until it smells toasty."])
        #expect(VoiceCatalog.sentences(in: "Hi, I'm Bella.") == ["Hi, I'm Bella."])
        #expect(VoiceCatalog.sentences(in: "Add the onions now. Done! Stir them well?")
            == ["Add the onions now. Done!", "Stir them well?"])
        #expect(VoiceCatalog.sentences(in: "   ").isEmpty)
        let long = String(repeating: "stir the pot, ", count: 40)
        let parts = VoiceCatalog.sentences(in: long, limit: 100)
        #expect(parts.count > 4)
        #expect(parts.allSatisfy { $0.count <= 100 && !$0.isEmpty })
        #expect(parts.joined(separator: " ").filter { $0 != " " } == long.filter { $0 != " " })
    }

    @Test func useAVoiceByKind() {
        #expect(VoiceCommand.parse("use the British voice") == .useVoice(.kind(accent: .british, gender: nil)))
        #expect(VoiceCommand.parse("use a male voice") == .useVoice(.kind(accent: nil, gender: .male)))
        #expect(VoiceCommand.parse("use an American woman") == .useVoice(.kind(accent: .american, gender: .female)))
        #expect(VoiceCommand.parse("use a British one") == .useVoice(.kind(accent: .british, gender: nil)))
        #expect(VoiceCommand.parse("use Samantha") == .useVoice(.named("samantha")))
        #expect(VoiceCommand.parse("use Bella") == .useVoice(.named("bella")))
        #expect(VoiceCommand.parse("use this one") == .useVoice(.highlighted))
        #expect(VoiceCommand.parse("next voice") == .nextVoice)
    }

    @Test func everyVoiceHasATwoWordCharacter() {
        for voice in VoiceCatalog.voices {
            let words = VoiceCatalog.character(pack: voice.pack).split(separator: " ")
            #expect(VoiceCatalog.characters[voice.pack] != nil, "\(voice.name) has no character")
            #expect(words.count == 2, "\(voice.name)")
        }
        #expect(VoiceCatalog.characters.count == VoiceCatalog.voices.count)
        #expect(VoiceCatalog.character(pack: VoiceCatalog.bellaAndSarah.pack) == "Blended voice")
    }
}
