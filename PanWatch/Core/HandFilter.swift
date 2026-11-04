import Foundation

/// Decides which of the hands Vision reports are real. Vision finds "hands" in wood grain
/// and in a shiny bag. Those flicker in for a frame, or sit perfectly still for as long as
/// the camera looks; a hand adding food stays put from frame to frame but moves over seconds.
struct HandFilter {
    /// Which hands count in one frame.
    struct Result: Equatable, Sendable {
        /// Indices, into the centroids passed in, of the hands that count.
        var counted: [Int] = []
        /// How many hands were seen but ignored because they haven't moved.
        var ignoredAsStill = 0
    }

    /// One hand followed from frame to frame.
    private struct Track {
        var spot: NormPoint
        var firstSeen: Double
        var lastSeen: Double
        /// Whether it was seen in each of the latest frames, oldest first.
        var seen: [Bool] = []
        /// Where it has been over the last `handStillDuration`.
        var path: [(time: Double, spot: NormPoint)] = []
        /// Where it sat when it was judged still. Nil while it can count.
        var stillAt: NormPoint?
        /// Whether, in each of the latest frames, it was far enough from `stillAt` to count again.
        var away: [Bool] = []
    }

    var settings: DetectorSettings
    private var tracks: [Track] = []

    init(settings: DetectorSettings = DetectorSettings()) {
        self.settings = settings
    }

    mutating func reset() {
        tracks.removeAll()
    }

    /// Feeds one analyzed frame: the joint centroid of each hand seen in it.
    mutating func update(_ centroids: [NormPoint], at time: Double) -> Result {
        // Pair each hand with the nearest track close enough to be the same hand, closest first.
        var pairs: [(distance: Double, hand: Int, track: Int)] = []
        for (hand, spot) in centroids.enumerated() {
            for (index, track) in tracks.enumerated() {
                let gap = Self.distance(spot, track.spot)
                if gap <= settings.handMatchDistance { pairs.append((gap, hand, index)) }
            }
        }
        var trackFor = [Int?](repeating: nil, count: centroids.count)
        var taken = Set<Int>()
        for pair in pairs.sorted(by: { $0.distance < $1.distance })
        where trackFor[pair.hand] == nil && !taken.contains(pair.track) {
            trackFor[pair.hand] = pair.track
            taken.insert(pair.track)
        }
        for index in tracks.indices where !taken.contains(index) {
            Self.push(false, onto: &tracks[index].seen, keeping: settings.handDebounceFrames)
        }

        var result = Result()
        for (hand, spot) in centroids.enumerated() {
            let index: Int
            if let matched = trackFor[hand] {
                index = matched
            } else {
                tracks.append(Track(spot: spot, firstSeen: time, lastSeen: time))
                index = tracks.count - 1
            }
            see(spot, at: time, on: index)
            if tracks[index].stillAt != nil {
                result.ignoredAsStill += 1
            } else if tracks[index].seen.filter({ $0 }).count >= settings.handDebounceHits {
                result.counted.append(hand)
            }
        }
        // Once a hand has been gone this long, its stillness no longer says anything.
        tracks.removeAll { time - $0.lastSeen > settings.handStillDuration }
        return result
    }

    private mutating func see(_ spot: NormPoint, at time: Double, on index: Int) {
        var track = tracks[index]
        track.spot = spot
        track.lastSeen = time
        Self.push(true, onto: &track.seen, keeping: settings.handDebounceFrames)
        track.path.append((time, spot))
        track.path.removeAll { $0.time < time - settings.handStillDuration }

        if let anchor = track.stillAt {
            // The move must hold like a new hand would, so one jumpy frame can't wake it.
            let isAway = Self.distance(spot, anchor) > settings.handResumeDistance
            Self.push(isAway, onto: &track.away, keeping: settings.handDebounceFrames)
            if track.away.filter({ $0 }).count >= settings.handDebounceHits {
                track.stillAt = nil
                track.away = []
            }
        } else if time - track.firstSeen >= settings.handStillDuration {
            let middle = HandGeometry.centroid(track.path.map(\.spot))
            if track.path.allSatisfy({ Self.distance($0.spot, middle) < settings.handStillDistance }) {
                track.stillAt = middle
            }
        }
        tracks[index] = track
    }

    private static func push(_ value: Bool, onto list: inout [Bool], keeping count: Int) {
        list.append(value)
        if list.count > count { list.removeFirst(list.count - count) }
    }

    private static func distance(_ a: NormPoint, _ b: NormPoint) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
