import Foundation

/// A small seeded generator (SplitMix64), so a scenario renders the same frames on every run
/// and on every machine.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// Seeds from a name with FNV-1a, which, unlike `hashValue`, is the same in every process.
    init(name: String) {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in name.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        self.init(seed: hash)
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0..<1.
    mutating func unit() -> Double {
        Double(next() >> 11) / 9_007_199_254_740_992.0
    }

    mutating func range(_ low: Double, _ high: Double) -> Double {
        low + (high - low) * unit()
    }

    mutating func chance(_ probability: Double) -> Bool {
        unit() < probability
    }

    /// Standard normal, by Box-Muller.
    mutating func gaussian() -> Double {
        let u = max(unit(), 1e-12)
        return (-2 * log(u)).squareRoot() * cos(2 * .pi * unit())
    }
}

/// 0 before `start`, 1 after `end`, eased in between.
func ramp(_ t: Double, _ start: Double, _ end: Double) -> Double {
    guard end > start else { return t >= end ? 1 : 0 }
    let x = min(1, max(0, (t - start) / (end - start)))
    return x * x * (3 - 2 * x)
}

/// 1 between `start` and `end`, with short eased edges.
func pulse(_ t: Double, _ start: Double, _ end: Double, edge: Double = 0.15) -> Double {
    ramp(t, start - edge, start) * (1 - ramp(t, end, end + edge))
}
