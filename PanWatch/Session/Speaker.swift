import AVFoundation

/// Reads prompts aloud in the voice the cook picked, or the most natural English voice on
/// the phone, and says when each prompt has finished, so the app can listen for an answer
/// without hearing itself.
@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var whenDone: [ObjectIdentifier: () -> Void] = [:]
    /// Utterances started and not yet finished or cut off.
    private var unfinished = 0
    /// Called with true when the app starts talking and false once it has stopped, so
    /// listening can pause in between.
    var onSpeakingChanged: ((Bool) -> Void)?

    nonisolated private static let voiceKey = "voiceIdentifier"
    /// The voice picked in the voice menu, kept between launches. Nil uses `best`.
    var voiceIdentifier: String? = UserDefaults.standard.string(forKey: Speaker.voiceKey) {
        didSet { UserDefaults.standard.set(voiceIdentifier, forKey: Self.voiceKey) }
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }

    /// Premium and enhanced voices sound far more human than the default one. They're
    /// free downloads in Settings > Accessibility > Read & Speak > Voices > English.
    /// Novelty voices are skipped. Without a better voice installed, the default is used.
    static let best: AVSpeechSynthesisVoice? = {
        let natural = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language == "en-US" && $0.quality != .default && !$0.voiceTraits.contains(.isNoveltyVoice)
        }
        return natural.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: "en-US")
    }()

    /// The picked voice while it's still on the phone (a Personal Voice also needs the
    /// cook's permission), otherwise `best`.
    static func voice(for identifier: String?) -> AVSpeechSynthesisVoice? {
        identifier.flatMap(AVSpeechSynthesisVoice.init(identifier:)) ?? best
    }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks `text`, cutting off anything still being said. `then` runs once the text
    /// has been spoken in full, not if it gets cut off. `voice` overrides the picked one,
    /// for playing a sample in the voice menu.
    func say(_ text: String, voice: String? = nil, then: (() -> Void)? = nil) {
        AudioSessionSetup.configure()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        } else {
            // Nothing is being said, so a count left over from a missed callback is stale;
            // left alone, it stopped listening from pausing while the app talks.
            unfinished = 0
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice(for: voice ?? voiceIdentifier)
        if let then {
            whenDone[ObjectIdentifier(utterance)] = then
        }
        unfinished += 1
        if unfinished == 1 { onSpeakingChanged?(true) }
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func ended() {
        // Once the synthesizer is quiet nothing is left to wait for, even if a callback was missed.
        unfinished = synthesizer.isSpeaking ? max(0, unfinished - 1) : 0
        if unfinished == 0 { onSpeakingChanged?(false) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            self.ended()
            self.whenDone.removeValue(forKey: id)?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            self.ended()
            _ = self.whenDone.removeValue(forKey: id)
        }
    }

    // MARK: Voice menu

    /// The English voices on the phone, best first, and the cook's Personal Voices once
    /// allowed. Novelty voices and the old robotic Eloquence voices are left out.
    nonisolated static func options() -> [VoiceOption] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in
                let personal = voice.voiceTraits.contains(.isPersonalVoice)
                return personal || (voice.language.hasPrefix("en")
                    && !voice.voiceTraits.contains(.isNoveltyVoice)
                    && !voice.identifier.contains("eloquence"))
            }
            .map { voice in
                let region = voice.language.split(separator: "-").last.map(String.init) ?? ""
                return VoiceOption(
                    id: voice.identifier,
                    name: voice.name,
                    quality: voice.quality,
                    region: Locale.current.localizedString(forRegionCode: region) ?? voice.language,
                    isPersonal: voice.voiceTraits.contains(.isPersonalVoice)
                )
            }
            .sorted { ($0.quality.rawValue, $1.name) > ($1.quality.rawValue, $0.name) }
    }

    /// Asks once to use the cook's Personal Voice; later calls return the answer at once.
    nonisolated static func requestPersonalVoice() async -> AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus {
        await withCheckedContinuation { continuation in
            AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

/// A voice the cook can pick in the voice menu.
struct VoiceOption: Identifiable, Equatable {
    let id: String
    let name: String
    let quality: AVSpeechSynthesisVoiceQuality
    /// "United States", "United Kingdom": the accent.
    let region: String
    let isPersonal: Bool
}
