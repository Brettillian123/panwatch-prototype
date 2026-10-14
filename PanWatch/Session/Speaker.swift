import AVFoundation

/// Reads prompts aloud with the most natural English voice on the phone, and says when
/// each prompt has finished, so the app can listen for an answer without hearing itself.
@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var whenDone: [ObjectIdentifier: () -> Void] = [:]
    /// Utterances started and not yet finished or cut off.
    private var unfinished = 0
    /// Called with true when the app starts talking and false once it has stopped, so
    /// listening can pause in between.
    var onSpeakingChanged: ((Bool) -> Void)?

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
        unfinished += 1
        if unfinished == 1 { onSpeakingChanged?(true) }
        synthesizer.speak(utterance)
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
}
