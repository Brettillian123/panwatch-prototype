import AVFoundation
import FluidAudio
import Observation

/// The cook's own voice: Kyutai's Pocket TTS (CC-BY-4.0) through FluidAudio 0.18.3's
/// `PocketTtsManager`, conditioned on the cook's own recording with `cloneVoice(from:)`.
/// The model downloads from Hugging Face the first time it's needed, into Application
/// Support. Until it's ready, and whenever it fails, `fallback` speaks instead (the voice
/// picked before this one), so a prompt is never lost.
///
/// Only a take made live by `VoiceRecorder` inside `OwnVoiceFlow` reaches `keep`; nothing
/// here reads an audio file the cook didn't just record. See `OwnVoice`.
@MainActor @Observable
final class OwnVoiceSource: SpeechSource {
    enum State: Equatable {
        /// Not downloaded on this phone yet, or not loaded since launch.
        case idle
        /// Downloading the model; the share done so far, from 0 to 1.
        case downloading(Double)
        /// Making the voice from the recording.
        case making
        case ready
        /// The last try failed; the next use tries again.
        case failed(String)
    }

    private(set) var state: State = .idle
    /// The cook's recorded voice, nil until one is kept.
    private(set) var saved: SavedOwnVoice? = OwnVoiceSource.loadSaved()

    /// Speaks a text the cook's voice can't yet: set by `Speaker`.
    @ObservationIgnored var fallback: ((
        _ text: String, _ format: AVAudioFormat,
        _ buffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        _ done: @escaping @Sendable (Bool) -> Void
    ) -> Void)?

    @ObservationIgnored private var manager: PocketTtsManager?
    @ObservationIgnored private var voice: PocketTtsVoiceData?
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var speaking: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    /// Bumped by every keep and delete, so a voice made from a replaced recording is dropped.
    @ObservationIgnored private var recordingNumber = 0

    /// About what the first download fetches for `precision: .int8` on the GPU placement,
    /// summed from FluidInference/pocket-tts-coreml `v2.1/english_2026-10` on 2026-11-09:
    /// cond_prefill 133.5 MB, flowlm_stepv2 77.1, flow_decoder_fused 19.3, mimi_decoder
    /// 41.9, constants_bin 181.6, plus the 44.4 MB Mimi encoder cloning needs. For the
    /// progress bar only.
    nonisolated static let expectedBytes: Int64 = 500_000_000

    /// The model, kept out of iCloud backups since it downloads again.
    nonisolated static let modelDirectory: URL = applicationSupport.appendingPathComponent("PocketTTS", isDirectory: true)
    /// The recording, the voice made from it, and its name. Kept out of backups too, so
    /// the recording never leaves the phone.
    nonisolated static let voiceDirectory: URL = applicationSupport.appendingPathComponent("OwnVoice", isDirectory: true)
    nonisolated private static let applicationSupport: URL =
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    nonisolated private static var recordingURL: URL { voiceDirectory.appendingPathComponent("recording.wav") }
    nonisolated private static var voiceURL: URL { voiceDirectory.appendingPathComponent("voice.bin") }
    nonisolated private static var infoURL: URL { voiceDirectory.appendingPathComponent("voice.json") }

    var isReady: Bool { state == .ready }

    // MARK: Keeping the recording

    /// Saves a take from `VoiceRecorder` as the cook's voice, replacing any before it, and
    /// starts making the voice from it.
    func keep(samples: [Float], name: String) throws {
        cancel()
        voice = nil
        recordingNumber += 1
        try Self.makeFolder(Self.voiceDirectory)
        try? FileManager.default.removeItem(at: Self.voiceURL)
        try Self.writeWAV(samples, to: Self.recordingURL)
        let info = SavedOwnVoice(
            name: OwnVoice.cleanName(name), seconds: Double(samples.count) / OwnVoice.sampleRate, recordedAt: .now)
        try JSONEncoder().encode(info).write(to: Self.infoURL, options: [.atomic, .completeFileProtection])
        saved = info
        if state == .ready || state == .making { state = .idle }
        prepare()
    }

    func rename(_ name: String) {
        guard var info = saved else { return }
        info.name = OwnVoice.cleanName(name)
        try? JSONEncoder().encode(info).write(to: Self.infoURL, options: [.atomic, .completeFileProtection])
        saved = info
    }

    /// Removes the recording and the voice made from it. The model stays for next time.
    func delete() {
        cancel()
        recordingNumber += 1
        voice = nil
        saved = nil
        try? FileManager.default.removeItem(at: Self.voiceDirectory)
        // A download under way finishes for next time; the load sees no recording and stops.
        if loading == nil { state = .idle }
    }

    // MARK: Loading

    /// Downloads and loads the model and makes the voice, if they aren't done or under way.
    func prepare() {
        guard saved != nil, loading == nil, !(state == .ready && voice != nil) else { return }
        state = manager == nil ? .downloading(Self.downloadedShare()) : .making
        loading = Task { [weak self] in
            await self?.load()
        }
    }

    private func load() async {
        do {
            let manager = try await loadedManager()
            while true {
                guard saved != nil else {
                    state = .idle
                    break
                }
                state = .making
                let number = recordingNumber
                let made = try await Self.makeVoice(with: manager)
                if number == recordingNumber, saved != nil {
                    voice = made
                    state = .ready
                    break
                }
                // Made from a recording since replaced or deleted.
                try? FileManager.default.removeItem(at: Self.voiceURL)
            }
        } catch {
            state = saved == nil ? .idle : .failed(error.localizedDescription)
        }
        loading = nil
    }

    private func loadedManager() async throws -> PocketTtsManager {
        if let manager { return manager }
        try Self.makeFolder(Self.modelDirectory)
        let made = PocketTtsManager(directory: Self.modelDirectory, precision: .int8)
        let watch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                let share = await Task.detached { OwnVoiceSource.downloadedShare() }.value
                guard let self, case .downloading = self.state else { return }
                self.state = .downloading(share)
            }
        }
        defer { watch.cancel() }
        try await made.initialize()
        manager = made
        return made
    }

    /// The saved voice, or a new one made from the recording and saved beside it.
    nonisolated private static func makeVoice(with manager: PocketTtsManager) async throws -> PocketTtsVoiceData {
        if FileManager.default.fileExists(atPath: voiceURL.path),
           let made = try? manager.loadClonedVoice(from: voiceURL) {
            return made
        }
        let clip = OwnVoice.cloneClip(try readWAV(recordingURL))
        guard Double(clip.count) / OwnVoice.sampleRate >= 1 else { throw OwnVoiceError.silent }
        let made = try await manager.cloneVoice(from: clip)
        try manager.saveClonedVoice(made, to: voiceURL)
        return made
    }

    /// The share of `expectedBytes` on disk, short of 1 until loading has finished.
    nonisolated static func downloadedShare() -> Double {
        guard let files = FileManager.default.enumerator(
            at: modelDirectory, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
        else { return 0 }
        var total: Int64 = 0
        for case let url as URL in files {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return min(0.99, Double(total) / Double(expectedBytes))
    }

    // MARK: SpeechSource

    func synthesize(
        _ text: String, voice _: String?, format: AVAudioFormat,
        buffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        done: @escaping @Sendable (Bool) -> Void
    ) {
        generation += 1
        let current = generation
        speaking?.cancel()
        guard let manager, let voice, state == .ready else {
            // Downloading, making, failed or none kept: the voice picked before says it.
            prepare()
            speakInstead(text, format: format, buffer: buffer, done: done)
            return
        }
        let sentences = VoiceCatalog.sentences(in: text)
        speaking = Task { [weak self] in
            var heard = false
            do {
                // One sentence at a time, streamed in 80 ms frames, so the first words
                // play while the rest are made.
                for sentence in sentences {
                    let frames = try await manager.synthesizeStreaming(text: sentence, voiceData: voice)
                    for try await frame in frames {
                        try Task.checkCancellation()
                        guard self?.generation == current else { return }
                        guard let pcm = KokoroVoice.buffer(
                            frame.samples, sampleRate: Int(OwnVoice.sampleRate), format: format)
                        else { throw OwnVoiceError.format }
                        if pcm.frameLength > 0 {
                            buffer(pcm)
                            heard = true
                        }
                    }
                }
                if self?.generation == current { done(true) }
            } catch {
                guard let self, self.generation == current, !Task.isCancelled else { return }
                if heard {
                    done(false)
                } else {
                    // Nothing played yet: the voice picked before says all of it.
                    self.speakInstead(text, format: format, buffer: buffer, done: done)
                }
            }
        }
    }

    func cancel() {
        generation += 1
        speaking?.cancel()
        speaking = nil
    }

    private func speakInstead(
        _ text: String, format: AVAudioFormat,
        buffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        done: @escaping @Sendable (Bool) -> Void
    ) {
        if let fallback {
            fallback(text, format, buffer, done)
        } else {
            done(false)
        }
    }

    // MARK: Files

    nonisolated private static func makeFolder(_ folder: URL) throws {
        var folder = folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
    }

    nonisolated private static func loadSaved() -> SavedOwnVoice? {
        guard FileManager.default.fileExists(atPath: recordingURL.path),
              let data = try? Data(contentsOf: infoURL)
        else { return nil }
        return try? JSONDecoder().decode(SavedOwnVoice.self, from: data)
    }

    /// 24 kHz mono float WAV.
    nonisolated private static func writeWAV(_ samples: [Float], to url: URL) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: OwnVoice.sampleRate, channels: 1, interleaved: false),
            let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(samples.count, 1))),
            let channel = pcm.floatChannelData?[0]
        else { throw OwnVoiceError.format }
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { channel.update(from: base, count: samples.count) }
        }
        pcm.frameLength = AVAudioFrameCount(samples.count)
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(
            forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: pcm)
        try (url as NSURL).setResourceValue(FileProtectionType.complete, forKey: .fileProtectionKey)
    }

    /// The recording this app made, back as 24 kHz mono floats.
    nonisolated private static func readWAV(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file.processingFormat.sampleRate == OwnVoice.sampleRate,
              let pcm = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        else { throw OwnVoiceError.format }
        try file.read(into: pcm)
        guard let channel = pcm.floatChannelData?[0] else { throw OwnVoiceError.format }
        return Array(UnsafeBufferPointer(start: channel, count: Int(pcm.frameLength)))
    }
}

enum OwnVoiceError: LocalizedError {
    case silent, format

    var errorDescription: String? {
        switch self {
        case .silent: "Too quiet. Record again, closer to the phone."
        case .format: "Something went wrong. Record again."
        }
    }
}
