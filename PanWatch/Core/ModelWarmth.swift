import Foundation

/// AI confirm prewarm: whether Apple's on-device model is loaded for the add check, so the
/// first add of a cook isn't the one that waits for the model to load and times out.
///
/// Apple's `prewarm` gives no signal when loading finishes, so "warm" means the model has
/// actually answered a check since it was last asked to load; until then it is "warming".
struct ModelWarmth: Equatable, Sendable {
    enum State: Equatable, Sendable {
        /// Nothing loaded, or the app went to the background and the system may have unloaded it.
        case cold
        /// Asked to load; no answer yet.
        case warming
        /// The model has answered since it was last asked to load.
        case warm
    }

    private(set) var state = State.cold
    /// A cook has asked for the model, so coming back from the background loads it again.
    private(set) var wanted = false

    /// A cook wants the model. True when the caller should start loading it now; false when
    /// it is already loading or loaded, so calling this many times does nothing more.
    mutating func request() -> Bool {
        wanted = true
        guard state == .cold else { return false }
        state = .warming
        return true
    }

    /// A check came back from the model (yes, no or unsure): it is loaded.
    mutating func answered() {
        state = .warm
    }

    /// The app went to the background; the system may unload the model.
    mutating func dropped() {
        state = .cold
    }

    /// The app is back. True when the caller should load the model again.
    mutating func returned() -> Bool {
        guard wanted else { return false }
        return request()
    }

    /// For the debug panel's AI CHECK section.
    func status(available: Bool) -> String {
        guard available else { return "Model not available on this phone" }
        switch state {
        case .cold: return "Model not loaded yet; it loads when a cook starts"
        case .warming: return "Model loading"
        case .warm: return "Model ready"
        }
    }
}
