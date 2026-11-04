import Foundation

/// Counts for one cook, for the gates that need them: three or fewer screen touches, and
/// how often the camera's offers get accepted.
struct CookStats: Equatable, Codable, Sendable {
    /// Taps on the cooking screen. Marking the pan and picking a recipe are setup and don't count.
    private(set) var screenTouches = 0
    private(set) var voiceCommands = 0
    /// Volume button and Camera Control presses.
    private(set) var buttonPresses = 0
    private(set) var offersMade = 0
    private(set) var offersAccepted = 0
    private(set) var offersDismissed = 0

    mutating func noteTouch() { screenTouches += 1 }
    mutating func noteVoice() { voiceCommands += 1 }
    mutating func noteButton() { buttonPresses += 1 }
    mutating func noteOffer() { offersMade += 1 }
    mutating func noteAccepted() { offersAccepted += 1 }
    mutating func noteDismissed() { offersDismissed += 1 }

    /// Share of offers accepted, or nil before the first offer.
    var acceptanceRate: Double? {
        offersMade == 0 ? nil : Double(offersAccepted) / Double(offersMade)
    }
}
