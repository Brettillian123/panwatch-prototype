import AVFoundation

/// Reads prompts aloud. Uses the playback audio category so it still speaks when the
/// phone is in silent mode, and mixes with any music that's playing.
@MainActor
final class Speaker {
    private let synthesizer = AVSpeechSynthesizer()
    private var configured = false

    func say(_ text: String) {
        if !configured {
            let audio = AVAudioSession.sharedInstance()
            try? audio.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
            try? audio.setActive(true)
            configured = true
        }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }
}
