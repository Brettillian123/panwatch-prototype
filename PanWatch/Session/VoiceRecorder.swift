import AVFoundation
import Observation

/// Records the cook reading the script, live from the microphone through the shared
/// engine (so echo cancellation still covers the app's own voice), at Pocket TTS's 24 kHz
/// mono. It has no way to take audio from a file: see `OwnVoice`. The take stays in memory
/// until the cook keeps it.
@MainActor @Observable
final class VoiceRecorder {
    /// The meter, 0 to 1.
    private(set) var level: Double = 0
    private(set) var seconds: Double = 0
    private(set) var isRecording = false
    private(set) var isPlaying = false
    /// The last take, 24 kHz mono.
    private(set) var samples: [Float] = []

    @ObservationIgnored private let audio: AudioIO
    @ObservationIgnored private var sink: CaptureSink?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var playback: Playback?

    init(audio: AudioIO) {
        self.audio = audio
    }

    /// Asks once for the microphone; later calls return the answer at once.
    nonisolated static func requestMicrophone() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /// Starts a take; `stopped` runs if it reaches `OwnVoice.maxSeconds` by itself.
    func start(stopped: @escaping @MainActor () -> Void) -> Bool {
        stopListening()
        let sink = CaptureSink()
        guard audio.startCapture({ buffer in sink.receive(buffer) }) else { return false }
        self.sink = sink
        samples = []
        seconds = 0
        level = 0
        isRecording = true
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, self.isRecording, let sink = self.sink else { return }
                let (count, rms) = sink.progress()
                self.seconds = Double(count) / OwnVoice.sampleRate
                self.level = OwnVoice.meter(rms: rms)
                if self.seconds >= OwnVoice.maxSeconds {
                    self.stop()
                    stopped()
                    return
                }
            }
        }
        return true
    }

    /// Ends the take and returns its length in seconds.
    @discardableResult func stop() -> Double {
        guard isRecording else { return seconds }
        audio.stopCapture()
        ticker?.cancel()
        ticker = nil
        isRecording = false
        level = 0
        samples = sink?.take() ?? []
        sink = nil
        seconds = Double(samples.count) / OwnVoice.sampleRate
        return seconds
    }

    /// Drops the take.
    func discard() {
        stop()
        stopListening()
        samples = []
        seconds = 0
    }

    /// Plays the take back through the engine.
    func listen() {
        stopListening()
        guard !samples.isEmpty, audio.start(),
              let buffer = KokoroVoice.buffer(samples, sampleRate: Int(OwnVoice.sampleRate), format: AudioIO.playbackFormat)
        else { return }
        let playback = Playback { [weak self] _ in
            Task { @MainActor in self?.playEnded() }
        }
        self.playback = playback
        isPlaying = true
        audio.player.play(buffer, playback)
        playback.finish()
    }

    func stopListening() {
        guard isPlaying else { return }
        playback = nil
        isPlaying = false
        audio.player.stop()
    }

    private func playEnded() {
        playback = nil
        isPlaying = false
    }
}

/// Microphone buffers converted to 24 kHz mono floats on the audio thread and kept.
private final class CaptureSink: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var lastRMS = 0.0
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private let output = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: OwnVoice.sampleRate, channels: 1, interleaved: false)!

    func receive(_ input: AVAudioPCMBuffer) {
        let rms = AudioIO.level(of: input)
        guard let converted = convert(input), let channel = converted.floatChannelData?[0] else { return }
        let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
        lock.withLock {
            samples.append(contentsOf: chunk)
            lastRMS = rms
        }
    }

    func progress() -> (Int, Double) {
        lock.withLock { (samples.count, lastRMS) }
    }

    func take() -> [Float] {
        lock.withLock { samples }
    }

    private func convert(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if converter == nil || inputFormat != input.format {
            inputFormat = input.format
            converter = AVAudioConverter(from: input.format, to: output)
        }
        guard let converter else { return nil }
        let ratio = output.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 64
        guard let result = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return nil }
        var given = false
        var error: NSError?
        let status = converter.convert(to: result, error: &error) { _, outStatus in
            if given {
                outStatus.pointee = .noDataNow
                return nil
            }
            given = true
            outStatus.pointee = .haveData
            return input
        }
        guard status != .error else { return nil }
        return result
    }
}
