import Foundation
import Testing
@testable import ClaudeBarCore

struct PaceTests {
    /// A five-hour window that started two and a half hours before noon, so half of it has passed.
    private func halfwayFiveHour(used: Double) -> WindowReading {
        WindowReading(kind: .fiveHour, usedPercentage: used, resetsAt: noon.adding(hours: 2.5), observedAt: noon)
    }

    @Test func elapsedShareComesFromResetTimeAndWindowLength() {
        let pace = Pace(reading: halfwayFiveHour(used: 50), now: noon)

        #expect(pace.elapsedFraction == 0.5)
        #expect(pace.delta == 0)
        #expect(pace.tone == .normal)
    }

    @Test(arguments: [(59.9, BarTone.normal), (60, .signal), (89.9, .signal), (90, .over), (100, .over)])
    func toneAtTheBoundaries(used: Double, expected: BarTone) {
        #expect(Pace(reading: halfwayFiveHour(used: used), now: noon).tone == expected)
    }

    @Test func nearlyExhaustedWinsOverBeingBehindPace() {
        let lateInWeek = WindowReading(kind: .sevenDay, usedPercentage: 92, resetsAt: noon.adding(hours: 1), observedAt: noon)

        let pace = Pace(reading: lateInWeek, now: noon)

        #expect(pace.delta < 0)
        #expect(pace.tone == .over)
    }

    @Test func elapsedShareIsClampedOutsideTheWindow() {
        let reading = halfwayFiveHour(used: 10)

        #expect(Pace(reading: reading, now: noon.adding(hours: -10)).elapsedFraction == 0)
        #expect(Pace(reading: reading, now: noon.adding(hours: 10)).elapsedFraction == 1)
    }

    @Test func menuBarShowsTheWindowWithTheLargerUsedShare() {
        let fiveHour = WindowReading(kind: .fiveHour, usedPercentage: 42, resetsAt: noon.adding(hours: 2), observedAt: noon)
        let sevenDay = WindowReading(kind: .sevenDay, usedPercentage: 61, resetsAt: noon.adding(hours: 50), observedAt: noon)
        let summary = LimitsSummary(fiveHour: .current(fiveHour), sevenDay: .current(sevenDay), costToday: 0, lastObservedAt: noon)

        #expect(summary.menuBarReading == sevenDay)
    }

    @Test func menuBarPrefersFiveHourOnATie() {
        let fiveHour = WindowReading(kind: .fiveHour, usedPercentage: 50, resetsAt: noon.adding(hours: 2), observedAt: noon)
        let sevenDay = WindowReading(kind: .sevenDay, usedPercentage: 50, resetsAt: noon.adding(hours: 50), observedAt: noon)
        let summary = LimitsSummary(fiveHour: .current(fiveHour), sevenDay: .current(sevenDay), costToday: 0, lastObservedAt: noon)

        #expect(summary.menuBarReading == fiveHour)
    }

    @Test func menuBarSkipsAWindowWhoseResetPassed() {
        let sevenDay = WindowReading(kind: .sevenDay, usedPercentage: 20, resetsAt: noon.adding(hours: 50), observedAt: noon)
        let summary = LimitsSummary(fiveHour: .resetPassed(at: noon), sevenDay: .current(sevenDay), costToday: 0, lastObservedAt: noon)

        #expect(summary.menuBarReading == sevenDay)
        #expect(LimitsSummary(fiveHour: nil, sevenDay: nil, costToday: 0, lastObservedAt: nil).menuBarReading == nil)
    }

    @Test func theSameFiguresObservedLaterGiveAnEqualMenuBarFigure() {
        let reset = noon.adding(hours: 2)
        let earlier = LimitsAggregator.summarize([limits("a", observedAt: noon, fiveHour: (41.6, reset))], now: noon, timeZone: kyiv)
        let later = LimitsAggregator.summarize([limits("a", observedAt: noon.adding(minutes: 1), fiveHour: (41.6, reset))], now: noon, timeZone: kyiv)

        #expect(earlier.menuBarReading != later.menuBarReading)
        #expect(earlier.menuBarFigure == later.menuBarFigure)
        #expect(later.menuBarFigure?.percent == "42%")
    }
}
