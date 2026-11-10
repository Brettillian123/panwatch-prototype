import Foundation
import Network
import Observation

/// Gets the natural voices onto the phone without the cook having to ask, and makes a tap
/// on a voice use it at once (`VoiceChoice`).
///
/// - Launch: once the first screen has settled, it loads the voices if they're here, or
///   starts fetching them on Wi-Fi (never on cellular or Low Data Mode on its own), and
///   picks up a fetch that was cut off.
/// - A tap on a voice that isn't here yet: the choice is kept, the fetch starts now on
///   Wi-Fi, and on cellular the cook is asked once (`askingMetered`). Offline, the row
///   goes back quietly and the fetch starts by itself when a connection returns.
@MainActor @Observable
final class VoiceFetcher {
    private(set) var choice: VoiceChoice
    private(set) var network: VoiceNetwork = .offline
    /// The one sheet: "You're not on Wi-Fi". Set once per attempt.
    var askingMetered = false

    /// Called when the voice that speaks changes by itself (a waited-for voice arrived).
    @ObservationIgnored var onSettled: ((String?) -> Void)?

    private let natural: KokoroVoice
    private let monitor = NWPathMonitor()
    @ObservationIgnored private var begun = false
    @ObservationIgnored private var knowsNetwork = false
    /// The cook said "Get them now" for the current attempt.
    @ObservationIgnored private var allowedMetered = false
    @ObservationIgnored private var packFetch: Task<Void, Never>?

    nonisolated private static let wantedKey = "wantedVoice"

    init(natural: KokoroVoice, settled: String?) {
        self.natural = natural
        choice = VoiceChoice(settled: settled, wanted: UserDefaults.standard.string(forKey: Self.wantedKey))
        natural.onStateChange = { [weak self] state in self?.naturalChanged(state) }
    }

    /// From launch: watches the network and, after a pause so the first screen is never
    /// slowed, loads or fetches the voices.
    func begin() {
        guard !begun else { return }
        begun = true
        monitor.pathUpdateHandler = Self.pathHandler(self)
        monitor.start(queue: DispatchQueue(label: "VoiceFetcher.path", qos: .utility))
        Task(priority: .utility) { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            self?.settle()
        }
    }

    @ObservationIgnored private var settledLaunch = false

    /// Made outside the main actor: the monitor calls it on its own queue.
    nonisolated private static func pathHandler(_ fetcher: VoiceFetcher) -> @Sendable (NWPath) -> Void {
        { [weak fetcher] path in
            let network = VoiceNetwork.from(
                satisfied: path.status == .satisfied, expensive: path.isExpensive, constrained: path.isConstrained)
            Task { @MainActor in fetcher?.networkChanged(network) }
        }
    }

    private func settle() {
        settledLaunch = true
        if KokoroVoice.isOnPhone {
            natural.prepare()
        } else {
            fetch(cookPicked: false)
        }
    }

    /// Whether `id` can speak this instant.
    func isReadyNow(_ id: String?) -> Bool {
        guard let pack = VoiceCatalog.pack(fromID: id) else { return true }
        return natural.hasPack(pack)
    }

    /// A tap, or "use ...": that voice is the app's voice from now on. Returns the voice
    /// that speaks now (the old one while a natural voice is on its way).
    @discardableResult
    func choose(_ id: String?) -> String? {
        let ready = isReadyNow(id)
        choice.choose(id, readyNow: ready)
        allowedMetered = false
        askingMetered = false
        save()
        if !ready, let id, let pack = VoiceCatalog.pack(fromID: id) {
            if natural.isReady {
                fetchPack(pack, for: id)
            } else if natural.isLoading {
                // Already on its way; it takes over when it lands.
            } else if KokoroVoice.isOnPhone {
                natural.prepare()
            } else {
                fetch(cookPicked: true)
            }
        }
        return choice.settled
    }

    /// The mixer was opened and needs the voices: asked for like a pick, with nothing chosen.
    func fetchForMixing() {
        allowedMetered = false
        fetch(cookPicked: true, forMixing: true)
    }

    /// "Get them now" on the sheet.
    func getNow() {
        askingMetered = false
        allowedMetered = true
        fetch(cookPicked: true)
    }

    /// "Wait for Wi-Fi" on the sheet: the choice is kept and the fetch starts on Wi-Fi.
    func waitForWiFi() {
        askingMetered = false
    }

    // MARK: Fetching

    private func fetch(cookPicked: Bool, forMixing: Bool = false) {
        guard !natural.isReady, !natural.isLoading else { return }
        if !knowsNetwork, !cookPicked { return } // the first path update decides
        let available = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        guard VoiceFetchRule.hasRoom(availableBytes: available) else {
            choice.failed(.noSpace)
            return
        }
        switch VoiceFetchRule.step(network: network, cookPicked: cookPicked, allowedMetered: allowedMetered) {
        case .start:
            natural.prepare()
        case .ask:
            if choice.wanted != nil || forMixing { askingMetered = true }
        case .wait:
            if cookPicked, network == .offline { choice.failed(.offline) }
        }
    }

    private func fetchPack(_ pack: String, for id: String) {
        packFetch?.cancel()
        packFetch = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                try await self.natural.fetchPack(pack)
                if self.choice.ready(id) { self.settledChanged() }
            } catch {
                guard self.choice.wanted == id else { return }
                self.choice.failed(KokoroVoice.problem(error))
                self.save()
            }
        }
    }

    private func networkChanged(_ network: VoiceNetwork) {
        let first = !knowsNetwork
        let changed = network != self.network
        self.network = network
        knowsNetwork = true
        guard settledLaunch, first || changed else { return }
        if network == .wifi, askingMetered { askingMetered = false }
        if network != .offline, choice.problem == .offline, let id = choice.retry() {
            save()
            if natural.isReady, let pack = VoiceCatalog.pack(fromID: id) {
                fetchPack(pack, for: id)
                return
            }
            fetch(cookPicked: true)
            return
        }
        // Picked up again by itself, on Wi-Fi only.
        fetch(cookPicked: false)
    }

    private func naturalChanged(_ state: KokoroVoice.State) {
        switch state {
        case .ready:
            let before = choice.settled
            if let wanted = choice.wanted, let pack = VoiceCatalog.pack(fromID: wanted), !natural.hasPack(pack) {
                fetchPack(pack, for: wanted)
            } else {
                choice.allReady()
            }
            if choice.settled != before { settledChanged() }
            save()
        case .failed(let problem):
            choice.failed(problem)
            save()
        case .idle, .downloading:
            break
        }
    }

    private func settledChanged() {
        save()
        onSettled?(choice.settled)
    }

    private func save() {
        UserDefaults.standard.set(choice.wanted, forKey: Self.wantedKey)
    }
}
