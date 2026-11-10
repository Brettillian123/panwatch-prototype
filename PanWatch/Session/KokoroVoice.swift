import AVFoundation
import FluidAudio
import Observation

/// The natural voices: Kokoro-82M on the phone through FluidAudio's Core ML runtime
/// (github.com/FluidInference/FluidAudio, Apache 2.0). `VoiceFetcher` starts the fetch from
/// Hugging Face on its own (Wi-Fi only unless the cook says otherwise), into Application
/// Support, and it is compiled for this phone once. Hearing a voice never waits for it: the
/// previews are bundled. Until it's ready, and whenever it fails, the phone's own voice
/// speaks instead, so a prompt is never lost.
@MainActor @Observable
final class KokoroVoice: SpeechSource {
    enum State: Equatable {
        /// Not downloaded on this phone yet, or not loaded since launch.
        case idle
        /// Downloading and compiling; the share done so far, from 0 to 1.
        case downloading(Double)
        case ready
        /// The last try failed; `VoiceFetcher` tries again when the network returns.
        case failed(VoiceChoice.Problem)
    }

    private(set) var state: State = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    /// Told of every change of `state`, for `VoiceFetcher`.
    @ObservationIgnored var onStateChange: ((State) -> Void)?
    /// The catalogue packs on the phone and loaded; a mix the cook made counts once loaded.
    @ObservationIgnored private(set) var packsHere: Set<String> = []
    /// The cook's mixes, saved between launches.
    private(set) var blends: [VoiceBlend] = KokoroVoice.loadBlends()

    private let fallback = AppleSpeechSource()
    @ObservationIgnored private var manager: KokoroAneManager?
    @ObservationIgnored private var store: KokoroAneModelStore?
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var speaking: Task<Void, Never>?
    private let generation = Generation()
    /// Kokoro's speed for the next text; `Speaker` sets it from the cook's choice.
    @ObservationIgnored var speed: VoiceSpeed = .normal
    /// The mix last played from the mixer, removed when the next one is made.
    @ObservationIgnored private var trialPack: String?

    /// About what the first download fetches: the seven v3 stages (118.8 MB of
    /// packages from the ANE-v3 manifest plus 82.2 MB of base stages), the English text
    /// front end, and the ten voices. For the progress bar only.
    nonisolated static let expectedBytes: Int64 = 232_000_000

    /// Everything Kokoro keeps on the phone, under Application Support, kept out of
    /// iCloud backups since it downloads again.
    nonisolated static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Kokoro", isDirectory: true)
    }()

    var isReady: Bool { state == .ready }

    var isLoading: Bool { loading != nil }

    /// Written once everything has arrived and loaded.
    nonisolated private static var marker: URL { directory.appendingPathComponent("fetched") }

    /// Everything is on the phone already, so loading needs no network. A fetch cut off
    /// part way is not: it goes back through `VoiceFetcher` and its network rule.
    nonisolated static var isOnPhone: Bool {
        VoiceFetchRule.arrivedEarlier(
            marker: FileManager.default.fileExists(atPath: marker.path), packFiles: packFiles())
    }

    /// The file names in the voices folder; empty when there is none yet.
    nonisolated private static func packFiles() -> [String] {
        guard let folder = try? voicesFolder() else { return [] }
        return (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    }

    /// `pack` can speak this instant.
    func hasPack(_ pack: String) -> Bool {
        state == .ready && (packsHere.contains(pack) || VoiceCatalog.voice(pack: pack) == nil)
    }

    /// Starts the fetch and load if they aren't done or under way. Only `VoiceFetcher`
    /// calls this when the voices aren't on the phone, since it decides about the network.
    func prepare() {
        guard manager == nil, loading == nil else { return }
        state = .downloading(Self.downloadedShare())
        loading = Task(priority: .utility) { [weak self] in
            await self?.load()
        }
    }

    /// Loads from the phone when everything is already here; never fetches.
    func prepareIfOnPhone() {
        if Self.isOnPhone { prepare() }
    }

    /// A catalogue voice whose pack didn't come down with the rest: fetched now.
    func fetchPack(_ pack: String) async throws {
        guard let store else { throw KokoroVoiceError.notReady }
        _ = try await store.voicePack(pack)
        packsHere.insert(pack)
    }

    private func load() async {
        do {
            var folder = Self.directory
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? folder.setResourceValues(values)
            let store = KokoroAneModelStore(directory: folder, version: .v3)
            let manager = KokoroAneManager(modelStore: store)
            let watch = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    let share = await Task.detached { KokoroVoice.downloadedShare() }.value
                    guard let self, case .downloading = self.state else { return }
                    self.state = .downloading(share)
                }
            }
            defer { watch.cancel() }
            try await manager.initialize()
            // The catalogue voices already on the phone, which needs no network, so a poor
            // connection can't hold up a voice that is here.
            let onDisk = Set(Self.packFiles())
            var here: Set<String> = []
            for voice in VoiceCatalog.voices where onDisk.contains("\(voice.pack).bin") {
                if (try? await store.voicePack(voice.pack)) != nil { here.insert(voice.pack) }
            }
            try? await rebuildBlends(store: store)
            // One short line, thrown away, so the first real line isn't late.
            let first = VoiceCatalog.defaultVoice.pack
            _ = try? await manager.synthesizeDetailed(
                text: "Ready.", voice: here.contains(first) ? first : here.first ?? first, speed: 1)
            FileManager.default.createFile(atPath: Self.marker.path, contents: Data())
            self.store = store
            self.manager = manager
            packsHere = here
            loading = nil
            state = .ready
            // The rest of the catalogue now, so a tap uses any of them at once; one that
            // fails to come down is fetched when it's chosen.
            for voice in VoiceCatalog.voices where !packsHere.contains(voice.pack) {
                if (try? await store.voicePack(voice.pack)) != nil { packsHere.insert(voice.pack) }
            }
            return
        } catch {
            loading = nil
            state = .failed(Self.problem(error))
        }
    }

    /// A full phone, or (anything else) the network.
    nonisolated static func problem(_ error: Error) -> VoiceChoice.Problem {
        var next: NSError? = error as NSError
        while let current = next {
            if VoiceFetchRule.problem(domain: current.domain, code: current.code) == .noSpace { return .noSpace }
            next = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        let text = String(describing: error).lowercased()
        return text.contains("no space") || text.contains("disk full") ? .noSpace : .offline
    }

    /// The share of `expectedBytes` on disk, short of 1 until loading has finished.
    nonisolated static func downloadedShare() -> Double {
        guard let files = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
        else { return 0 }
        var total: Int64 = 0
        for case let url as URL in files {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return min(0.99, Double(total) / Double(expectedBytes))
    }

    // MARK: SpeechSource

    func synthesize(
        _ text: String, voice: String?, format: AVAudioFormat,
        buffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        done: @escaping @Sendable (Bool) -> Void
    ) {
        let current = generation.next()
        speaking?.cancel()
        guard let pack = VoiceCatalog.pack(fromID: voice), let manager, state == .ready else {
            // Still arriving, failed, or not a natural voice: the phone's voice says it.
            prepareIfOnPhone()
            fallback.rate = AVSpeechUtteranceDefaultSpeechRate * speed.factor
            fallback.synthesize(text, voice: nil, format: format, buffer: buffer, done: done)
            return
        }
        let sentences = VoiceCatalog.sentences(in: text)
        let rate = self.speed.factor
        let generation = self.generation
        speaking = Task.detached(priority: .userInitiated) {
            do {
                // One sentence at a time, so the first plays while the next is made.
                for sentence in sentences {
                    try Task.checkCancellation()
                    let result = try await manager.synthesizeDetailed(text: sentence, voice: pack, speed: rate)
                    guard generation.isCurrent(current) else { return }
                    guard let pcm = Self.buffer(result.samples, sampleRate: result.sampleRate, format: format) else {
                        done(false)
                        return
                    }
                    if pcm.frameLength > 0 { buffer(pcm) }
                }
                if generation.isCurrent(current) { done(true) }
            } catch {
                if generation.isCurrent(current), !Task.isCancelled { done(false) }
            }
        }
    }

    func cancel() {
        generation.next()
        speaking?.cancel()
        speaking = nil
        fallback.cancel()
    }

    /// Kokoro's mono float samples in the engine's format (24 kHz mono float, the same
    /// rate Kokoro makes); nil if the rates ever differ.
    nonisolated static func buffer(_ samples: [Float], sampleRate: Int, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard Double(sampleRate) == format.sampleRate, format.commonFormat == .pcmFormatFloat32,
              format.channelCount == 1,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(samples.count, 1))),
              let channel = pcm.floatChannelData?[0]
        else { return nil }
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { channel.update(from: base, count: samples.count) }
        }
        pcm.frameLength = AVAudioFrameCount(samples.count)
        return pcm
    }

    // MARK: Mixes

    nonisolated private static let blendsKey = "kokoroBlends"
    nonisolated private static let blendNumberKey = "kokoroBlendNumber"

    /// The built-in Bella and Sarah mix, then the cook's own.
    var allBlends: [VoiceBlend] { [VoiceCatalog.bellaAndSarah] + blends }

    /// Mixes two voices at `balance` into a pack Kokoro can speak, and returns its id.
    /// `name` nil makes a trial mix for Hear it, replacing the last trial.
    func makeBlend(first: String, second: String, balance: Double, name: String?) async throws -> String {
        guard let store, state == .ready else { throw KokoroVoiceError.notReady }
        let defaults = UserDefaults.standard
        let number = defaults.integer(forKey: Self.blendNumberKey) + 1
        defaults.set(number, forKey: Self.blendNumberKey)
        guard let pack = VoiceCatalog.blendPack(first: first, second: second, balance: balance, number: number) else {
            throw KokoroVoiceError.badVoice
        }
        try await writeBlend(VoiceBlend(name: name ?? "", first: first, second: second, balance: balance, pack: pack), store: store)
        if let name {
            blends.append(VoiceBlend(name: name, first: first, second: second, balance: balance, pack: pack))
            Self.saveBlends(blends)
        } else {
            if let old = trialPack, let folder = try? Self.voicesFolder() {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(old).bin"))
            }
            trialPack = pack
        }
        return VoiceCatalog.idPrefix + pack
    }

    func removeBlend(_ pack: String) {
        blends.removeAll { $0.pack == pack }
        Self.saveBlends(blends)
        if let folder = try? Self.voicesFolder() {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(pack).bin"))
        }
    }

    /// Writes any saved mix whose pack is missing (a fresh model folder, say).
    private func rebuildBlends(store: KokoroAneModelStore) async throws {
        let folder = try Self.voicesFolder()
        for blend in allBlends where !FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(blend.pack).bin").path) {
            try await writeBlend(blend, store: store)
        }
    }

    /// FluidAudio has no blend call. A Kokoro voice is a 510 x 256 table of floats, and
    /// the v3 runtime loads any English pack it finds at `voices/<name>.bin` in its model
    /// folder (KokoroAneV3Assets.ensureVoice), so a mix is the weighted mean of two packs
    /// written there.
    private func writeBlend(_ blend: VoiceBlend, store: KokoroAneModelStore) async throws {
        let a = try await store.voicePack(blend.first)
        let b = try await store.voicePack(blend.second)
        guard let mixed = VoiceCatalog.mix(a.storage, b.storage, balance: blend.balance) else {
            throw KokoroVoiceError.badVoice
        }
        let pack = try KokoroAneVoicePack(storage: mixed)
        let folder = try Self.voicesFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try pack.binaryData.write(to: folder.appendingPathComponent("\(blend.pack).bin"), options: .atomic)
    }

    /// `voices/` in the English v3 model folder:
    /// `Kokoro/kokoro-82m-coreml/ANE-v3/<release revision>/en/voices`, as FluidAudio's
    /// KokoroAne.md documents it. The revision folder is the one holding the manifest.
    nonisolated static func voicesFolder() throws -> URL {
        let releases = directory.appendingPathComponent("kokoro-82m-coreml/ANE-v3", isDirectory: true)
        let revisions = try FileManager.default.contentsOfDirectory(at: releases, includingPropertiesForKeys: nil)
        guard let english = revisions
            .map({ $0.appendingPathComponent("en", isDirectory: true) })
            .first(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("manifest.json").path) })
        else { throw KokoroVoiceError.notReady }
        return english.appendingPathComponent("voices", isDirectory: true)
    }

    nonisolated private static func loadBlends() -> [VoiceBlend] {
        guard let data = UserDefaults.standard.data(forKey: blendsKey) else { return [] }
        return (try? JSONDecoder().decode([VoiceBlend].self, from: data)) ?? []
    }

    nonisolated private static func saveBlends(_ blends: [VoiceBlend]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(blends), forKey: blendsKey)
    }

    /// Bumped for every text, so audio from a cut-off one is dropped.
    private final class Generation: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        @discardableResult func next() -> Int {
            lock.withLock {
                value += 1
                return value
            }
        }

        func isCurrent(_ id: Int) -> Bool {
            lock.withLock { value == id }
        }
    }
}

enum KokoroVoiceError: LocalizedError {
    case notReady, badVoice

    var errorDescription: String? {
        switch self {
        case .notReady: "The voices are almost ready. Try again in a moment."
        case .badVoice: "Those two can't be mixed. Pick another pair."
        }
    }
}
