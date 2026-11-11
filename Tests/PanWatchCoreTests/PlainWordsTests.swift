import Testing
@testable import PanWatchCore

/// Brett, Nov 10: technical jargon "will appear as clutter and confuse them". No word a cook
/// sees in the help list or hears in a fixed spoken line may come from the inside of the app.
@Suite("Plain words")
struct PlainWordsTests {
    static let banned = PlainWords.banned

    static func bannedWords(in text: String) -> [String] {
        PlainWords.bannedWords(in: text)
    }

    static let findings: [SetupCalibration.Finding] = [
        .noPicture, .tooDark, .tooBright, .handNotSeen, .lowContrast, .handSmall, .restless, .flicker, .lookalike,
    ]

    @Test func helpAndSpokenLinesUsePlainWords() {
        var lines = HelpGroup.allCases.flatMap { [$0.title] + $0.phrases }
        lines += Self.findings.flatMap { [$0.title, $0.fix, "\($0.title). \($0.fix)"] }
        lines += [AssistantRails.outOfScope, AssistantRails.unsure, FoodSafety.cannotTell, OwnVoice.consentLine, OwnVoice.defaultName]
        lines += VoiceCatalog.voices.map(\.detail)
        for line in lines {
            #expect(Self.bannedWords(in: line).isEmpty, "\(line)")
        }
    }

    @Test func theCheckCatchesJargon() {
        #expect(Self.bannedWords(in: "Natural voices need a download, about 230 MB.") == ["mb"])
        #expect(Self.bannedWords(in: "Lights flicker") == ["flicker"])
        #expect(Self.bannedWords(in: "Play a sample").count == 1)
        #expect(Self.bannedWords(in: "Turn on a light near the stove.").isEmpty)
    }
}
