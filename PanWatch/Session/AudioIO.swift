import AVFoundation

/// One audio engine for listening and speaking. Speech plays through it, and its input
/// runs with voice processing, so the system cancels the app's own voice from the
/// microphone and the cook can be heard over it (Apple: `AVAudioIONode.setVoiceProcessingEnabled`,
/// iOS 13+, throws; enabling it on the input node enables it on the output node too, and
/// it must be set before the engine starts. With the `.playAndRecord` category and no
/// chat mode set, the system switches the session to `.voiceChat` on its own, which is
/// what applies echo cancellation and gain control:
/// https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct/voicechat
/// https://developer.apple.com/documentation/avfaudio/avaudioionode/setvoiceprocessingenabled(_:)
/// Voice chat mode drops AirPlay mirroring, which the app doesn't use.)
/// If voice processing can't be enabled, the engine still runs and `voiceProcessing` is
/// false, so listening pauses while the app talks, as before.
@MainActor
final class AudioIO {
    private(set) var engine = AVAudioEngine()
    /// Plays speech buffers; shared by every voice.
    private(set) var player = SpeechPlayer()
    /// The format speech is played in. Every voice converts its audio to this; the mixer
    /// resamples it to the output.
    nonisolated static let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    /// Echo cancellation is on, so the microphone can keep listening while the app talks.
    private(set) var voiceProcessing = false
    private var prepared = false
    private var tapInstalled = false
    /// The microphone's two takers: listening, and a recording of the cook's own voice.
    private let taps = MicTaps()

    var isRunning: Bool { engine.isRunning }

    /// Microphone audio, in the input's format, from the audio thread. Installed once the
    /// engine is prepared (voice processing changes the input format), and again after a reset.
    func installTap(_ block: @escaping AVAudioNodeTapBlock) {
        taps.listen = block
        if prepared { addTap() }
    }

    func removeTap() {
        taps.listen = nil
        removeTapIfUnused()
    }

    /// Microphone audio for a recording of the cook's own voice, beside listening, from the
    /// audio thread. False when the engine can't start.
    func startCapture(_ block: @escaping @Sendable (AVAudioPCMBuffer) -> Void) -> Bool {
        taps.record = block
        guard start() else {
            stopCapture()
            return false
        }
        addTap()
        return tapInstalled
    }

    func stopCapture() {
        taps.record = nil
        removeTapIfUnused()
    }

    private func removeTapIfUnused() {
        guard tapInstalled, !taps.inUse else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    /// Starts the engine, setting it up first if needed. False when the microphone or the
    /// audio session can't be started yet; the caller tries again later.
    func start() -> Bool {
        if engine.isRunning { return true }
        AudioSessionSetup.configure()
        guard prepare() else { return false }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.stop()
            return false
        }
        return true
    }

    func stop() {
        player.stop()
        if engine.isRunning { engine.stop() }
    }

    /// After a media services reset every audio object is dead, so a new engine is built.
    func rebuild() {
        stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0) }
        tapInstalled = false
        prepared = false
        voiceProcessing = false
        engine = AVAudioEngine()
        player = SpeechPlayer()
    }

    private func prepare() -> Bool {
        if prepared { return true }
        let input = engine.inputNode
        do {
            try input.setVoiceProcessingEnabled(true)
            voiceProcessing = true
        } catch {
            voiceProcessing = false
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            if voiceProcessing {
                try? input.setVoiceProcessingEnabled(false)
                voiceProcessing = false
            }
            return false
        }
        player.attach(to: engine, format: Self.playbackFormat)
        prepared = true
        addTap()
        return true
    }

    private func addTap() {
        guard !tapInstalled, taps.inUse else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tapBlock(feeding: taps))
        tapInstalled = true
    }

    /// Made outside the main actor: the tap runs on the audio thread.
    nonisolated private static func tapBlock(feeding taps: MicTaps) -> AVAudioNodeTapBlock {
        { buffer, time in taps.deliver(buffer, time) }
    }

    /// RMS of a buffer's first channel, full scale 1.0; 0 for a format without floats.
    nonisolated static func level(of buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let samples = data[0]
        var sum = 0.0
        for i in 0..<Int(buffer.frameLength) {
            let s = Double(samples[i])
            sum += s * s
        }
        return (sum / Double(buffer.frameLength)).squareRoot()
    }
}

/// Who takes the microphone's audio, read on the audio thread and set on the main one.
final class MicTaps: @unchecked Sendable {
    private let lock = NSLock()
    private var listenBlock: AVAudioNodeTapBlock?
    private var recordBlock: (@Sendable (AVAudioPCMBuffer) -> Void)?

    var listen: AVAudioNodeTapBlock? {
        get { lock.withLock { listenBlock } }
        set { lock.withLock { listenBlock = newValue } }
    }

    var record: (@Sendable (AVAudioPCMBuffer) -> Void)? {
        get { lock.withLock { recordBlock } }
        set { lock.withLock { recordBlock = newValue } }
    }

    var inUse: Bool { lock.withLock { listenBlock != nil || recordBlock != nil } }

    func deliver(_ buffer: AVAudioPCMBuffer, _ time: AVAudioTime) {
        let (listen, record) = lock.withLock { (listenBlock, recordBlock) }
        listen?(buffer, time)
        record?(buffer)
    }
}

/// The player node, driven from whatever thread a voice delivers its audio on. Buffers
/// are played in order; `Playback` says when the last one has been heard.
final class SpeechPlayer: @unchecked Sendable {
    private let node = AVAudioPlayerNode()
    private weak var engine: AVAudioEngine?

    func attach(to engine: AVAudioEngine, format: AVAudioFormat) {
        self.engine = engine
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    /// Queues `buffer`; `playback` is told once it has been heard.
    func play(_ buffer: AVAudioPCMBuffer, _ playback: Playback) {
        guard let engine, engine.isRunning else {
            playback.failed()
            return
        }
        playback.scheduled()
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in playback.played() }
        if !node.isPlaying { node.play() }
    }

    /// Drops whatever is queued.
    func stop() {
        node.stop()
    }
}

/// One utterance's progress through the player: the voice schedules buffers as they're
/// made, then says it has finished; once every buffer has been heard, `onDone` runs.
final class Playback: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = 0
    private var finished = false
    private var ended = false
    private let onDone: @Sendable (Bool) -> Void

    init(onDone: @escaping @Sendable (Bool) -> Void) {
        self.onDone = onDone
    }

    func scheduled() {
        lock.withLock { pending += 1 }
    }

    func played() {
        let done: Bool = lock.withLock {
            pending -= 1
            guard pending == 0, finished, !ended else { return false }
            ended = true
            return true
        }
        if done { onDone(true) }
    }

    /// The voice has made all its audio; `ok` false means it failed part way.
    func finish(ok: Bool = true) {
        let done: Bool = lock.withLock {
            finished = true
            guard !ended, !ok || pending == 0 else { return false }
            ended = true
            return true
        }
        if done { onDone(ok) }
    }

    func failed() {
        finish(ok: false)
    }
}
