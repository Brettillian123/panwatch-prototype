import Foundation

/// How well the app's offers match what really happened, scored against hand-labeled
/// clips. The Nov 4 gate is an F1 of 0.70 or better.
struct DetectionScore: Equatable, Sendable {
    /// Offers that matched a real addition.
    let truePositives: Int
    /// Offers with no real addition near them: false alarms.
    let falsePositives: Int
    /// Real additions the app never offered for.
    let misses: Int

    /// Share of offers that were right. 1 when the app offered nothing.
    var precision: Double {
        let offers = truePositives + falsePositives
        return offers == 0 ? 1 : Double(truePositives) / Double(offers)
    }

    /// Share of real additions the app caught. 1 when nothing was added.
    var recall: Double {
        let real = truePositives + misses
        return real == 0 ? 1 : Double(truePositives) / Double(real)
    }

    /// Balances catching everything against raising false alarms; 1 is perfect.
    var f1: Double {
        let sum = precision + recall
        return sum == 0 ? 0 : 2 * precision * recall / sum
    }

    /// Matches each labeled time (seconds into a clip, when food really went in) with the
    /// nearest unmatched offer within `tolerance` seconds. Each offer matches at most one label.
    static func score(labeled: [Double], detected: [Double], tolerance: Double = 2.0) -> DetectionScore {
        var unmatched = detected.sorted()
        var matches = 0
        for label in labeled.sorted() {
            let nearest = unmatched.indices.min { abs(unmatched[$0] - label) < abs(unmatched[$1] - label) }
            if let nearest, abs(unmatched[nearest] - label) <= tolerance {
                unmatched.remove(at: nearest)
                matches += 1
            }
        }
        return DetectionScore(
            truePositives: matches,
            falsePositives: unmatched.count,
            misses: labeled.count - matches
        )
    }

    /// False alarms per hour of watched time, the second Nov 4 gate. Nil with no watched time.
    static func falseAlarmsPerHour(falsePositives: Int, watchedSeconds: Double) -> Double? {
        guard watchedSeconds > 0 else { return nil }
        return Double(falsePositives) / (watchedSeconds / 3600)
    }
}
