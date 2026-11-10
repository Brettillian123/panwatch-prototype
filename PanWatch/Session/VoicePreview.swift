import AVFoundation

/// The recorded previews shipped in the app (Resources/VoicePreviews/<pack>.m4a), one per
/// catalogue voice, made with the same Kokoro runtime (Tools/VoicePreviews). They play the
/// moment the app is installed, offline, before any voice has arrived.
enum VoicePreview {
    /// The bundled preview for a catalogue voice id; nil for a mix, the cook's own voice
    /// or an Apple voice, which are spoken live.
    static func url(for voiceID: String?) -> URL? {
        guard let pack = VoiceCatalog.pack(fromID: voiceID), VoiceCatalog.previewFile(pack: pack) != nil else { return nil }
        return Bundle.main.url(forResource: pack, withExtension: "m4a", subdirectory: "VoicePreviews")
            ?? Bundle.main.url(forResource: pack, withExtension: "m4a")
    }
}

/// Plays one bundled clip through the same engine as every other voice, so muting,
/// echo cancelling and "stop" treat it like speech. The text is ignored: the clip says it.
@MainActor
final class ClipSource: SpeechSource {
    /// The clip the next `synthesize` plays.
    var clip: URL?
    private var decoded: [URL: AVAudioPCMBuffer] = [:]

    func synthesize(
        _ text: String, voice: String?, format: AVAudioFormat,
        buffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        done: @escaping @Sendable (Bool) -> Void
    ) {
        guard let clip, let pcm = decoded[clip] ?? Self.decode(clip, to: format) else {
            done(false)
            return
        }
        decoded[clip] = pcm
        buffer(pcm)
        done(true)
    }

    func cancel() {}

    /// The whole clip in the engine's format (24 kHz mono float); a few seconds, so read
    /// at once.
    static func decode(_ url: URL, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let file = try? AVAudioFile(forReading: url),
              let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: source)) != nil
        else { return nil }
        if source.format == format { return source }
        guard let converter = AVAudioConverter(from: source.format, to: format) else { return nil }
        let ratio = format.sampleRate / source.format.sampleRate
        let capacity = AVAudioFrameCount((Double(source.frameLength) * ratio).rounded(.up)) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var given = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if given {
                outStatus.pointee = .endOfStream
                return nil
            }
            given = true
            outStatus.pointee = .haveData
            return source
        }
        return status == .error || output.frameLength == 0 ? nil : output
    }
}
