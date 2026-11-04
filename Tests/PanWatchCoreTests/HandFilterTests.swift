import Testing
@testable import PanWatchCore

@Suite("Hand filter")
struct HandFilterTests {
    /// Feeds a `HandFilter` at 15 fps, the rate the app analyzes at.
    private struct Feed {
        var filter = HandFilter()
        var time = 0.0

        /// One frame with a hand at each of `spots`.
        mutating func frame(_ spots: [NormPoint]) -> HandFilter.Result {
            defer { time += Timeline.frameInterval }
            return filter.update(spots, at: time)
        }

        /// `seconds` of frames; `spots` receives the frame's index within this stretch.
        /// Returns each frame's result.
        mutating func hold(_ seconds: Double, spots: (Int) -> [NormPoint]) -> [HandFilter.Result] {
            let count = Int((seconds / Timeline.frameInterval).rounded())
            return (0..<count).map { frame(spots($0)) }
        }
    }

    private let spot = NormPoint(x: 0.4, y: 0.5)

    /// Drifts right by `step` of the frame each frame.
    private func moving(from start: NormPoint, step: Double) -> (Int) -> [NormPoint] {
        { [NormPoint(x: start.x + Double($0) * step, y: start.y)] }
    }

    @Test func aStillHandIsIgnored() throws {
        // Wood grain Vision mistakes for a hand: it never moves.
        var feed = Feed()
        let results = feed.hold(3.0) { _ in [spot] }
        #expect(results[15].counted == [0])
        let last = try #require(results.last)
        #expect(last.counted.isEmpty)
        #expect(last.ignoredAsStill == 1)
    }

    @Test func aMovingHandCounts() throws {
        var feed = Feed()
        let hand = moving(from: NormPoint(x: 0.2, y: 0.2), step: 0.005)
        let results = feed.hold(3.0) { hand($0) + [spot] }
        // Counts from its second frame on, while the still one beside it is dropped.
        #expect(results.dropFirst().allSatisfy { $0.counted.contains(0) })
        let last = try #require(results.last)
        #expect(last.counted == [0])
        #expect(last.ignoredAsStill == 1)
    }

    @Test func aOneFrameFlickerDoesNotCount() {
        var feed = Feed()
        let results = [feed.frame([spot]), feed.frame([]), feed.frame([]), feed.frame([NormPoint(x: 0.8, y: 0.2)])]
        #expect(results.allSatisfy { $0.counted.isEmpty })
    }

    @Test func aStillHandThatMovesCountsAgain() throws {
        var feed = Feed()
        let still = try #require(feed.hold(3.0) { _ in [spot] }.last)
        #expect(still.counted.isEmpty)

        // One jumpy frame isn't a move.
        let jump = feed.frame([NormPoint(x: spot.x + 0.06, y: spot.y)])
        #expect(jump.counted.isEmpty)
        #expect(feed.frame([spot]).counted.isEmpty)

        let moved = try #require(feed.hold(0.5, spots: moving(from: spot, step: 0.01)).last)
        #expect(moved.counted == [0])
        #expect(moved.ignoredAsStill == 0)
    }
}
