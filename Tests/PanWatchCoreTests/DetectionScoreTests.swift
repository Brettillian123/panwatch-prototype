import Testing
@testable import PanWatchCore

@Suite("Detection score")
struct DetectionScoreTests {
    @Test func perfectMatch() {
        let score = DetectionScore.score(labeled: [10, 30], detected: [10.5, 29])
        #expect(score == DetectionScore(truePositives: 2, falsePositives: 0, misses: 0))
        #expect(score.f1 == 1)
    }

    @Test func nothingToFindAndNothingFound() {
        let score = DetectionScore.score(labeled: [], detected: [])
        #expect(score.precision == 1)
        #expect(score.recall == 1)
    }

    @Test func everythingMissed() {
        let score = DetectionScore.score(labeled: [10, 20], detected: [])
        #expect(score.misses == 2)
        #expect(score.recall == 0)
        #expect(score.f1 == 0)
    }

    @Test func onlyFalseAlarms() {
        let score = DetectionScore.score(labeled: [], detected: [5])
        #expect(score.falsePositives == 1)
        #expect(score.precision == 0)
        #expect(score.f1 == 0)
    }

    @Test func toleranceEdgeCounts() {
        #expect(DetectionScore.score(labeled: [10], detected: [12]).truePositives == 1)
        #expect(DetectionScore.score(labeled: [10], detected: [12.01]).truePositives == 0)
    }

    @Test func twoOffersForOneAdditionIsOneFalseAlarm() {
        let score = DetectionScore.score(labeled: [10], detected: [9.5, 10.5])
        #expect(score == DetectionScore(truePositives: 1, falsePositives: 1, misses: 0))
    }

    @Test func orderDoesNotMatter() {
        let sorted = DetectionScore.score(labeled: [10, 40, 70], detected: [11, 39, 100])
        let shuffled = DetectionScore.score(labeled: [70, 10, 40], detected: [100, 11, 39])
        #expect(sorted == shuffled)
        #expect(sorted == DetectionScore(truePositives: 2, falsePositives: 1, misses: 1))
    }

    @Test func mixedResultGivesF1() {
        // 2 right, 1 false alarm, 1 miss: precision and recall are both 2/3.
        let score = DetectionScore.score(labeled: [10, 40, 70], detected: [11, 39, 100])
        #expect(abs(score.f1 - 2.0 / 3.0) < 1e-9)
    }

    @Test func falseAlarmsPerHour() {
        #expect(DetectionScore.falseAlarmsPerHour(falsePositives: 3, watchedSeconds: 1800) == 6)
        #expect(DetectionScore.falseAlarmsPerHour(falsePositives: 3, watchedSeconds: 0) == nil)
    }
}
