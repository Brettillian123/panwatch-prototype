import Foundation

/// A running timer as it's saved, so it survives the app being closed and reopened.
struct SavedTimer: Codable, Equatable, Sendable {
    /// The same id as the timer's system alarm, so the alarm can still be cancelled.
    let id: UUID
    let label: String
    let start: Date
    let end: Date
}

enum SavedTimers {
    static func encode(_ timers: [SavedTimer]) -> Data {
        (try? JSONEncoder().encode(timers)) ?? Data()
    }

    /// Empty for missing or damaged data, never a crash.
    static func decode(_ data: Data) -> [SavedTimer] {
        (try? JSONDecoder().decode([SavedTimer].self, from: data)) ?? []
    }

    /// The timers that haven't finished by `now`, in their saved order.
    static func stillRunning(_ timers: [SavedTimer], at now: Date) -> [SavedTimer] {
        timers.filter { $0.end > now }
    }
}
