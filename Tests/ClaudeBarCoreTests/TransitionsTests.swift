import Foundation
import Testing
@testable import ClaudeBarCore

struct TransitionDetectorTests {
    @Test func firstReadIsABaselineWithoutNotices() {
        var detector = TransitionDetector()

        #expect(detector.notices(in: [event("a", .done), event("b", .waiting)], now: noon).isEmpty)
    }

    @Test func announcesMovesIntoDoneAndWaitingOnly() {
        var detector = TransitionDetector()
        _ = detector.notices(in: [event("a", .working), event("b", .working), event("c", .done)], now: noon)

        let notices = detector.notices(in: [
            event("a", .done, at: noon.adding(minutes: 1)),
            event("b", .waiting, at: noon.adding(minutes: 1)),
            event("c", .working, at: noon.adding(minutes: 1)),
        ], now: noon)

        #expect(notices.map(\.sessionID) == ["a", "b"])
    }

    @Test func rereadingTheSameStateIsSilent() {
        var detector = TransitionDetector()
        _ = detector.notices(in: [event("a", .working)], now: noon)
        let done = event("a", .done, at: noon.adding(minutes: 1))
        _ = detector.notices(in: [done], now: noon)

        #expect(detector.notices(in: [done], now: noon).isEmpty)
    }

    @Test func aNewerEventInTheSameStateIsAnnouncedAgain() {
        var detector = TransitionDetector()
        _ = detector.notices(in: [event("a", .waiting)], now: noon)

        let notices = detector.notices(in: [event("a", .waiting, at: noon.adding(minutes: 2))], now: noon)

        #expect(notices.map(\.sessionID) == ["a"])
    }

    @Test func aSessionFirstSeenAfterTheBaselineIsAnnounced() {
        var detector = TransitionDetector()
        _ = detector.notices(in: [], now: noon)

        #expect(detector.notices(in: [event("new", .waiting)], now: noon).map(\.sessionID) == ["new"])
        #expect(detector.notices(in: [event("other", .working)], now: noon).isEmpty)
    }

    @Test func anOldRecordFirstSeenIsNotAnnounced() {
        var detector = TransitionDetector()
        _ = detector.notices(in: [], now: noon)

        let notices = detector.notices(in: [event("refilled", .done, at: noon.adding(hours: -11))], now: noon)

        #expect(notices.isEmpty)
        #expect(detector.notices(in: [event("fresh", .done, at: noon.adding(minutes: -4))], now: noon).map(\.sessionID) == ["fresh"])
    }
}

struct ThresholdTrackerTests {
    private func summary(fiveHour used: Double, resetsAt: Date) -> LimitsSummary {
        let reading = WindowReading(kind: .fiveHour, usedPercentage: used, resetsAt: resetsAt, observedAt: noon)
        return LimitsSummary(fiveHour: .current(reading), sevenDay: nil, costToday: 0, lastObservedAt: noon)
    }

    @Test func alertsOnceWhenTheThresholdIsReached() {
        var tracker = ThresholdTracker()
        let reset = noon.adding(hours: 2)

        #expect(tracker.alerts(for: summary(fiveHour: 79.9, resetsAt: reset), threshold: 80).isEmpty)
        #expect(tracker.alerts(for: summary(fiveHour: 80, resetsAt: reset), threshold: 80).count == 1)
        #expect(tracker.alerts(for: summary(fiveHour: 95, resetsAt: reset), threshold: 80).isEmpty)
    }

    @Test func aSlightlyShiftedResetIsTheSameWindow() {
        var tracker = ThresholdTracker()
        _ = tracker.alerts(for: summary(fiveHour: 85, resetsAt: noon.adding(hours: 2)), threshold: 80)

        #expect(tracker.alerts(for: summary(fiveHour: 86, resetsAt: noon.adding(hours: 2).adding(minutes: 59)), threshold: 80).isEmpty)
    }

    @Test func theNextWindowAlertsAgain() {
        var tracker = ThresholdTracker()
        _ = tracker.alerts(for: summary(fiveHour: 85, resetsAt: noon.adding(hours: 2)), threshold: 80)

        #expect(tracker.alerts(for: summary(fiveHour: 81, resetsAt: noon.adding(hours: 7)), threshold: 80).count == 1)
    }

    @Test func rememberedAlertsSurviveARestart() {
        var first = ThresholdTracker()
        _ = first.alerts(for: summary(fiveHour: 85, resetsAt: noon.adding(hours: 2)), threshold: 80)
        var restarted = ThresholdTracker(alerted: first.alerted)

        #expect(restarted.alerts(for: summary(fiveHour: 85, resetsAt: noon.adding(hours: 2)), threshold: 80).isEmpty)
    }
}
