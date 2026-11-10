import Foundation

/// Which voice the cook picked, which one speaks, and which is still on its way.
///
/// A tap uses a voice at once. A natural voice that isn't on the phone yet is `wanted`:
/// its row shows a ring, the voice in `settled` keeps speaking, and the moment it is ready
/// it takes over with no message. A failed fetch leaves it wanted with a `problem`, so the
/// row quietly goes back to unchosen and it is fetched again once the network returns.
/// A second pick before the first is ready replaces it (the last tap wins).
struct VoiceChoice: Equatable, Sendable {
    enum Problem: Equatable, Sendable {
        /// No connection, or the cook chose to wait for Wi-Fi.
        case offline
        /// The phone is too full to keep the voices.
        case noSpace

        /// The one caption under the list; nothing else ever mentions the fetch.
        var caption: String {
            switch self {
            case .offline: "Connect to Wi-Fi to use this voice."
            case .noSpace: "Free up some space to use this voice."
            }
        }
    }

    /// The voice that speaks now: an Apple voice, the cook's own, or a natural voice on the
    /// phone. Nil is the phone's best built-in voice.
    private(set) var settled: String?
    /// A natural voice picked before it is on the phone.
    private(set) var wanted: String?
    /// Why `wanted` has stopped waiting; nil while it is on its way.
    private(set) var problem: Problem?

    init(settled: String? = nil, wanted: String? = nil) {
        self.settled = settled
        self.wanted = wanted == settled ? nil : wanted
    }

    /// The row with the check or the ring: the wanted voice while it's on its way,
    /// otherwise the one speaking.
    var marked: String? {
        if let wanted, problem == nil { return wanted }
        return settled
    }

    /// The wanted voice is on its way: its row shows the ring instead of the check.
    func isPending(_ id: String) -> Bool {
        wanted == id && problem == nil
    }

    /// A tap or "use ...". `readyNow`: the voice can speak this instant (not a natural
    /// voice, or a natural voice whose model and pack are on the phone).
    mutating func choose(_ id: String?, readyNow: Bool) {
        problem = nil
        if readyNow || id == nil {
            settled = id
            wanted = nil
        } else {
            wanted = id
        }
    }

    /// A natural voice finished arriving. Returns true when it was the wanted one, which
    /// now speaks.
    @discardableResult
    mutating func ready(_ id: String) -> Bool {
        guard wanted == id else { return false }
        settled = id
        wanted = nil
        problem = nil
        return true
    }

    /// Everything arrived: the wanted voice, whichever it is, now speaks.
    mutating func allReady() {
        if let wanted { ready(wanted) }
    }

    /// The fetch for the wanted voice stopped.
    mutating func failed(_ problem: Problem) {
        guard wanted != nil else { return }
        self.problem = problem
    }

    /// The network came back (or space was freed): the voice to fetch again, if any.
    mutating func retry() -> String? {
        guard let wanted, problem != nil else { return nil }
        problem = nil
        return wanted
    }
}

/// The phone's connection, as the fetch rule sees it.
enum VoiceNetwork: Equatable, Sendable {
    case wifi
    /// Cellular, a personal hotspot, or Low Data Mode: an expensive or constrained path.
    case metered
    case offline

    /// From the path monitor's flags.
    static func from(satisfied: Bool, expensive: Bool, constrained: Bool) -> VoiceNetwork {
        guard satisfied else { return .offline }
        return expensive || constrained ? .metered : .wifi
    }
}

/// When to fetch the natural voices.
enum VoiceFetchRule {
    enum Step: Equatable, Sendable {
        case start
        /// Ask the cook first (the one sheet): only when they picked a voice on a metered path.
        case ask
        case wait
    }

    /// `cookPicked`: the cook just picked a voice that isn't here. `allowedMetered`: they
    /// said "Get them now" for this attempt. On its own the app only fetches on Wi-Fi.
    static func step(network: VoiceNetwork, cookPicked: Bool, allowedMetered: Bool) -> Step {
        switch network {
        case .wifi: .start
        case .offline: .wait
        case .metered:
            if allowedMetered { .start } else if cookPicked { .ask } else { .wait }
        }
    }

    /// The connection changed while a picked voice waits after a failed fetch: whether to
    /// try again by itself. It never asks: the one sheet only ever follows a tap, so a
    /// phone coming back on cellular keeps waiting for Wi-Fi unless the cook already said
    /// "Get them now". `packOnly`: the voices are loaded and only this voice's small file
    /// is missing, which any connection may fetch.
    static func retriesByItself(network: VoiceNetwork, allowedMetered: Bool, packOnly: Bool) -> Bool {
        if network == .offline { return false }
        return packOnly || step(network: network, cookPicked: false, allowedMetered: allowedMetered) == .start
    }

    /// Whether the voices fully arrived on an earlier run, so loading them needs no network.
    /// `marker`: the file written after a load that finished. `packFiles`: the file names in
    /// the voices folder. Builds from before the marker fetched the other catalogue voices
    /// only after everything else had arrived and loaded, so one of those on the phone
    /// proves it. The folder alone, or the first voice alone, proves nothing: a fetch cut
    /// off part way leaves those behind.
    static func arrivedEarlier(marker: Bool, packFiles: [String]) -> Bool {
        if marker { return true }
        let first = VoiceCatalog.defaultVoice.pack
        let here = Set(packFiles)
        return VoiceCatalog.voices.contains { $0.pack != first && here.contains("\($0.pack).bin") }
    }

    /// About what the first fetch keeps on the phone, with room to spare for compiling.
    static let neededBytes: Int64 = 400_000_000

    static func hasRoom(availableBytes: Int64?) -> Bool {
        guard let availableBytes else { return true }
        return availableBytes >= neededBytes
    }

    /// A failed fetch's error, by domain and code: a full disk, or (anything else) the
    /// network, which is retried when the connection returns.
    static func problem(domain: String, code: Int) -> VoiceChoice.Problem {
        switch (domain, code) {
        case ("NSCocoaErrorDomain", 640), ("NSCocoaErrorDomain", 642), ("NSPOSIXErrorDomain", 28):
            .noSpace
        default:
            .offline
        }
    }
}
