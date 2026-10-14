import AVFoundation

/// Reads prompts aloud with the most natural English voice on the phone, and says when
/// each prompt has finished, so the app can listen for an answer without hearing itself.
@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var whenDone: [ObjectIdentifier: () -> Void] = [:]

    /// Premium and enhanced voices sound far more human than the default one. They're
    /// free downloads in Settings > Accessibility > Spoken Content > Voices > English.
    /// Novelty voices are skipped. Without a better voice installed, the default is used.
    private static let voice: AVSpeechSynthesisVoice? = {
        let natural = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language == "en-US" && $0.quality != .default && !$0.voiceTraits.contains(.isNoveltyVoice)
        }
        return natural.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: "en-US")
    }()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks `text`, cutting off anything still being said. `then` runs once the text
    /// has been spoken in full, not if it gets cut off.
    func say(_ text: String, then: (() -> Void)? = nil) {
        AudioSessionSetup.configure()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice
        if let then {
            whenDone[ObjectIdentifier(utterance)] = then
        }
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.whenDone.removeValue(forKey: id)?() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in _ = self.whenDone.removeValue(forKey: id) }
    }
}
