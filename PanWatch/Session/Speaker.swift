import AVFoundation

/// A voice: text in, PCM audio out. The Apple voice below is one; other voices plug in
/// here and play through the same engine.
protocol SpeechSource: AnyObject {
    /// Makes the audio for `text` in `voice` (an `AVSpeechSynthesisVoice` identifier,
    /// where the voice supports one), handing each chunk to `buffer` in `format`, then
    /// calling `done` once: true when all the audio was made, false when it failed.
    /// Both may be called from any thread. `cancel()` stops a text part way; after it,
    /// nothing more is called for that text. Both methods are called on the main actor.
    @MainActor func synthesize(
        _ text: String, voice: String?, format: AVAudioFormat,
        buffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        done: @escaping @Sendable (Bool) -> Void
    )
    @MainActor func cancel()
}

/// Reads prompts aloud in the voice the cook picked, or the most natural English voice on
/// the phone, through the shared audio engine, and says when each prompt has finished.
/// With voice processing on, the microphone keeps listening while the app talks and the
/// cook can cut a prompt short by speaking; without it, listening pauses in between.
@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private let audio: AudioIO
    /// The phone's own voices. Replaced to switch to another voice.
    var source: SpeechSource = AppleSpeechSource()
    /// The natural (Kokoro) voices, for any voice id `VoiceCatalog` marks as natural.
    let natural = KokoroVoice()
    /// The cook's own recorded voice (Pocket TTS), for `OwnVoice.id`.
    let own = OwnVoiceSource()
    /// The bundled voice previews.
    private let clips = ClipSource()

    nonisolated private static let speedKey = "voiceSpeed"
    /// How fast every voice talks, kept between launches.
    var speed: VoiceSpeed = UserDefaults.standard.string(forKey: Speaker.speedKey).flatMap(VoiceSpeed.init(rawValue:)) ?? .normal {
        didSet { UserDefaults.standard.set(speed.rawValue, forKey: Self.speedKey) }
    }
    /// Speaks straight to the output when the engine can't start: no echo cancellation,
    /// so listening pauses for it.
    private let direct = AVSpeechSynthesizer()
    /// Runs once the current prompt has been spoken in full.
    private var whenDone: (() -> Void)?
    /// Bumped for every prompt, so callbacks from a cut-off one are ignored.
    private var utterance = 0
    private var playback: Playback?
    private var stuckGuard: Task<Void, Never>?
    /// What the app is saying right now, for the self-echo guard. Nil when quiet.
    private(set) var currentText: String?
    /// The current prompt plays through the engine with voice processing, so the
    /// microphone doesn't hear it and listening can go on.
    private(set) var cancelsEcho = false
    /// Called with true when the app starts talking and false once it has stopped.
    var onSpeakingChanged: ((Bool) -> Void)?

    nonisolated private static let voiceKey = "voiceIdentifier"
    /// The voice picked in the voice menu, kept between launches. Nil uses `best`.
    var voiceIdentifier: String? = UserDefaults.standard.string(forKey: Speaker.voiceKey) {
        didSet {
            UserDefaults.standard.set(voiceIdentifier, forKey: Self.voiceKey)
            if OwnVoice.isOwn(voiceIdentifier) {
                ownFallback = OwnVoice.fallback(previous: oldValue, current: ownFallback)
                own.prepare()
            }
        }
    }

    nonisolated private static let ownFallbackKey = "ownVoiceFallback"
    /// The voice picked before the cook's own; it speaks while that one loads or if it fails.
    private(set) var ownFallback: String? = UserDefaults.standard.string(forKey: Speaker.ownFallbackKey) {
        didSet { UserDefaults.standard.set(ownFallback, forKey: Self.ownFallbackKey) }
    }

    var isSpeaking: Bool { currentText != nil }

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

    init(audio: AudioIO) {
        self.audio = audio
        super.init()
        direct.delegate = self
        // The natural voices load in the background once launch has settled (VoiceFetcher).
        if OwnVoice.isOwn(voiceIdentifier) {
            own.prepare()
        }
        own.fallback = { [weak self] text, format, buffer, done in
            guard let self else { return done(false) }
            self.speakInstead(text, format: format, buffer: buffer, done: done)
        }
    }

    /// The cook's own voice isn't ready or failed: the voice picked before it says `text`.
    private func speakInstead(
        _ text: String, format: AVAudioFormat,
        buffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        done: @escaping @Sendable (Bool) -> Void
    ) {
        let id = ownFallback
        if VoiceCatalog.isNatural(id) {
            natural.speed = speed
            natural.synthesize(text, voice: id, format: format, buffer: buffer, done: done)
        } else {
            (source as? AppleSpeechSource)?.rate = AVSpeechUtteranceDefaultSpeechRate * speed.factor
            source.synthesize(text, voice: id, format: format, buffer: buffer, done: done)
        }
    }

    /// Speaks `text`, cutting off anything still being said. `then` runs once the text
    /// has been spoken in full, not if it gets cut off. `voice` overrides the picked one,
    /// for playing a sample in the voice menu.
    /// `earcon` plays first, through the same engine, so echo cancellation covers it too;
    /// with empty `text`, the earcon is all that plays.
    /// `clip`: a bundled recording that says `text`, played instead of making the audio.
    func say(_ text: String, voice: String? = nil, clip: URL? = nil, earcon: Earcon? = nil, then: (() -> Void)? = nil) {
        cutOff()
        // An earcon can't play without the engine; the words still can.
        if text.isEmpty, earcon == nil || !audio.start() {
            then?()
            return
        }
        utterance += 1
        let id = utterance
        let chosen = voice ?? voiceIdentifier
        currentText = text
        whenDone = then
        guard audio.start() else {
            cancelsEcho = false
            onSpeakingChanged?(true)
            speakDirectly(text, voice: chosen, id: id)
            return
        }
        // Set before the listener is told, since it decides from this whether to pause.
        cancelsEcho = audio.voiceProcessing
        onSpeakingChanged?(true)
        let player = audio.player
        let playback = Playback { [weak self] ok in
            Task { @MainActor in self?.playbackEnded(id: id, ok: ok, text: text, voice: chosen) }
        }
        self.playback = playback
        let voiceSource: SpeechSource
        if let clip {
            clips.clip = clip
            voiceSource = clips
        } else if OwnVoice.isOwn(chosen) {
            voiceSource = own
        } else if VoiceCatalog.isNatural(chosen) {
            natural.speed = speed
            voiceSource = natural
        } else {
            (source as? AppleSpeechSource)?.rate = AVSpeechUtteranceDefaultSpeechRate * speed.factor
            voiceSource = source
        }
        if let earcon, let buffer = Self.buffer(for: earcon) {
            player.play(buffer, playback)
        }
        if text.isEmpty {
            playback.finish()
        } else {
            voiceSource.synthesize(text, voice: chosen, format: AudioIO.playbackFormat, buffer: { buffer in
                player.play(buffer, playback)
            }, done: { ok in
                playback.finish(ok: ok)
            })
        }
        // A prompt that never reports back (the engine died under it) would leave the app
        // "speaking" for good; no prompt takes longer than this.
        let limit = 5.0 + 0.5 * Double(SelfEcho.words(in: text).count) / Double(speed.factor)
        stuckGuard = Task { [weak self] in
            try? await Task.sleep(for: .seconds(limit))
            guard let self, !Task.isCancelled, self.utterance == id, self.currentText != nil else { return }
            self.ended(id: id, finished: false)
        }
    }

    func stop() {
        cutOff()
    }

    /// The earcon's samples in the playback format, made once each.
    private static var earconBuffers: [Earcon: AVAudioPCMBuffer] = [:]
    private static func buffer(for earcon: Earcon) -> AVAudioPCMBuffer? {
        if let made = earconBuffers[earcon] { return made }
        let format = AudioIO.playbackFormat
        let samples = earcon.samples(sampleRate: format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        for (i, sample) in samples.enumerated() { channel[i] = sample }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        earconBuffers[earcon] = buffer
        return buffer
    }

    /// Stops the current prompt without finishing it.
    private func cutOff() {
        guard currentText != nil else { return }
        let id = utterance
        source.cancel()
        natural.cancel()
        own.cancel()
        audio.player.stop()
        if direct.isSpeaking { direct.stopSpeaking(at: .immediate) }
        ended(id: id, finished: false)
    }

    private func playbackEnded(id: Int, ok: Bool, text: String, voice: String?) {
        guard id == utterance, currentText != nil else { return }
        if ok || text.isEmpty {
            ended(id: id, finished: ok)
        } else {
            // The voice or the engine failed part way: say it the plain way instead.
            audio.player.stop()
            speakDirectly(text, voice: voice, id: id)
        }
    }

    private func speakDirectly(_ text: String, voice: String?, id: Int) {
        cancelsEcho = false
        playback = nil
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice(for: OwnVoice.isOwn(voice) ? ownFallback : voice)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * speed.factor
        direct.speak(utterance)
    }

    private func ended(id: Int, finished: Bool) {
        guard id == utterance else { return }
        stuckGuard?.cancel()
        stuckGuard = nil
        playback = nil
        currentText = nil
        cancelsEcho = false
        let then = whenDone
        whenDone = nil
        onSpeakingChanged?(false)
        if finished { then?() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.currentText == utterance.speechString else { return }
            self.ended(id: self.utterance, finished: true)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.currentText == utterance.speechString else { return }
            self.ended(id: self.utterance, finished: false)
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

/// Apple's voices, including Personal Voice, rendered to buffers instead of played, so
/// they go through the engine where voice processing can cancel them from the microphone.
final class AppleSpeechSource: SpeechSource, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    /// The speaking rate for the next text; `Speaker` sets it from the cook's speed.
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    private let lock = NSLock()
    /// Bumped for every text, so buffers from a cancelled one are dropped.
    private var generation = 0

    @MainActor func synthesize(
        _ text: String, voice: String?, format: AVAudioFormat,
        buffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        done: @escaping @Sendable (Bool) -> Void
    ) {
        let current: Int = lock.withLock {
            generation += 1
            return generation
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Speaker.voice(for: voice)
        utterance.rate = rate
        let state = Conversion(format: format)
        synthesizer.write(utterance) { [weak self] audio in
            guard let self, self.lock.withLock({ self.generation == current }) else { return }
            guard let pcm = audio as? AVAudioPCMBuffer else { return }
            if pcm.frameLength == 0 {
                // An empty buffer marks the end of the text.
                done(!state.failed)
                return
            }
            guard !state.failed else { return }
            if let converted = state.convert(pcm) {
                if converted.frameLength > 0 { buffer(converted) }
            } else {
                state.failed = true
                done(false)
            }
        }
    }

    @MainActor func cancel() {
        lock.withLock { generation += 1 }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    /// Converts the synthesizer's buffers (its own rate and sample type) to the engine's
    /// format. One converter per text, since a rate change carries state between buffers.
    private final class Conversion: @unchecked Sendable {
        let format: AVAudioFormat
        var converter: AVAudioConverter?
        var failed = false

        init(format: AVAudioFormat) {
            self.format = format
        }

        func convert(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
            if input.format == format { return input }
            if converter == nil || converter?.inputFormat != input.format {
                converter = AVAudioConverter(from: input.format, to: format)
            }
            guard let converter else { return nil }
            let ratio = format.sampleRate / input.format.sampleRate
            let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 64
            guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
            var given = false
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, outStatus in
                if given {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                given = true
                outStatus.pointee = .haveData
                return input
            }
            return status == .error ? nil : output
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
    /// A Kokoro voice from `VoiceCatalog`, or one of the cook's mixes.
    var isNatural = false
    /// One line in plain words under a natural voice's name.
    var detail = ""
    var accent: VoiceAccent?
    var gender: VoiceGender?
    /// The cook's own recorded voice.
    var isOwn = false

    init(
        id: String, name: String, quality: AVSpeechSynthesisVoiceQuality, region: String, isPersonal: Bool
    ) {
        self.id = id
        self.name = name
        self.quality = quality
        self.region = region
        self.isPersonal = isPersonal
    }

    init(natural voice: NaturalVoice) {
        self.init(id: voice.id, name: voice.name, quality: .premium, region: voice.accent.title, isPersonal: false)
        isNatural = true
        detail = voice.detail
        accent = voice.accent
        gender = voice.gender
    }

    init(own voice: SavedOwnVoice) {
        self.init(id: OwnVoice.id, name: voice.name, quality: .premium, region: "Recorded by you", isPersonal: false)
        isOwn = true
    }
}
