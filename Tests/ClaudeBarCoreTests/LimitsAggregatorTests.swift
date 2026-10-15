import Foundation
import Testing
@testable import ClaudeBarCore

struct LimitsAggregatorTests {
    @Test func noRecordsMeansNoWindowsAndZeroCost() {
        let summary = LimitsAggregator.summarize([], now: noon, timeZone: kyiv)

        #expect(summary.fiveHour == nil)
        #expect(summary.sevenDay == nil)
        #expect(summary.costToday == 0)
        #expect(summary.lastObservedAt == nil)
    }

    @Test func eachWindowIsSummarisedIndependently() {
        let reset = noon.adding(hours: 2)
        let weekReset = noon.adding(hours: 50)
        let records = [
            limits("old", observedAt: noon.adding(minutes: -30), fiveHour: (10, reset), sevenDay: (40, weekReset)),
            limits("new", observedAt: noon.adding(minutes: -5), fiveHour: (25, reset)),
        ]

        let summary = LimitsAggregator.summarize(records, now: noon, timeZone: kyiv)

        #expect(summary.fiveHour == .current(WindowReading(kind: .fiveHour, usedPercentage: 25, resetsAt: reset, observedAt: noon.adding(minutes: -5))))
        #expect(summary.sevenDay == .current(WindowReading(kind: .sevenDay, usedPercentage: 40, resetsAt: weekReset, observedAt: noon.adding(minutes: -30))))
        #expect(summary.lastObservedAt == noon.adding(minutes: -5))
    }

    @Test func aSessionRewritingOlderFiguresDoesNotLowerTheWindow() {
        let reset = noon.adding(hours: 2)
        let records = [
            limits("busy", observedAt: noon.adding(minutes: -5), fiveHour: (30, reset)),
            limits("idle", observedAt: noon, fiveHour: (19, reset)),
        ]

        let summary = LimitsAggregator.summarize(records, now: noon, timeZone: kyiv)

        #expect(summary.fiveHour == .current(WindowReading(kind: .fiveHour, usedPercentage: 30, resetsAt: reset, observedAt: noon.adding(minutes: -5))))
    }

    @Test func readingsOfAnEarlierWindowAreLeftOut() {
        let records = [
            limits("before", observedAt: noon.adding(hours: -2), fiveHour: (90, noon.adding(hours: -1))),
            limits("after", observedAt: noon, fiveHour: (5, noon.adding(hours: 4))),
        ]

        let summary = LimitsAggregator.summarize(records, now: noon, timeZone: kyiv)

        #expect(summary.fiveHour == .current(WindowReading(kind: .fiveHour, usedPercentage: 5, resetsAt: noon.adding(hours: 4), observedAt: noon)))
    }

    @Test func usageOutsideZeroToAHundredIsClamped() {
        let reset = noon.adding(hours: 2)
        let high = LimitsAggregator.summarize([limits("a", fiveHour: (1e19, reset))], now: noon, timeZone: kyiv)
        let low = LimitsAggregator.summarize([limits("a", fiveHour: (-5, reset))], now: noon, timeZone: kyiv)

        #expect(high.menuBarReading?.usedPercentage == 100)
        #expect(low.menuBarReading?.usedPercentage == 0)
    }

    @Test func eachProfileGetsItsOwnSummary() {
        let reset = noon.adding(hours: 2)
        let records = [
            limits("personal", observedAt: noon.adding(minutes: -1), fiveHour: (90, reset), cost: 7),
            limits("work", observedAt: noon, fiveHour: (20, noon.adding(hours: 3)), cost: 2, configDir: "/Users/me/.claude-work"),
        ]

        let summaries = LimitsAggregator.summarizeProfiles(records, now: noon, timeZone: kyiv)

        #expect(summaries.map(\.profile) == [".claude", ".claude-work"])
        #expect(summaries.map(\.configDir) == [nil, "/Users/me/.claude-work"])
        #expect(summaries.map { $0.menuBarReading?.usedPercentage } == [90, 20])
        #expect(summaries.map(\.costToday) == [7, 2])
    }

    @Test func theMenuBarShowsTheMostUrgentProfileAndNamesIt() {
        let records = [
            limits("personal", observedAt: noon, fiveHour: (30, noon.adding(hours: 2))),
            limits("work", observedAt: noon.adding(minutes: -5), fiveHour: (85, noon.adding(hours: 3)), configDir: "/Users/me/.claude-work"),
        ]

        let figure = LimitsAggregator.menuBarFigure(of: LimitsAggregator.summarizeProfiles(records, now: noon, timeZone: kyiv))

        #expect(figure?.percent == "85%")
        #expect(figure?.profile == ".claude-work")
    }

    @Test func oneProfileIsNotNamed() {
        let records = [limits("a", fiveHour: (30, noon.adding(hours: 2)), configDir: "/Users/me/.claude-work")]

        let summaries = LimitsAggregator.summarizeProfiles(records, now: noon, timeZone: kyiv)

        #expect(summaries.map(\.profile) == [nil])
        #expect(LimitsAggregator.menuBarFigure(of: summaries)?.profile == nil)
    }

    @Test func aClaudeFolderElsewhereKeepsItsParentInTheName() {
        #expect(LimitsAggregator.profileName(nil) == ".claude")
        #expect(LimitsAggregator.profileName("/Users/me/work/.claude") == "work/.claude")
        #expect(LimitsAggregator.profileName("/Users/me/.claude-work") == ".claude-work")
    }

    @Test func aPlanWithoutLimitsIsKnownOnlyAfterClaudeAnswered() {
        let beforeTheFirstReply = LimitsAggregator.summarize([limits("api", cost: 0)], now: noon, timeZone: kyiv)
        let afterIt = LimitsAggregator.summarize([limits("api", cost: 3.5, answered: true)], now: noon, timeZone: kyiv)

        #expect(!beforeTheFirstReply.planReportsNoLimits)
        #expect(afterIt.planReportsNoLimits)
        #expect(afterIt.costToday == 3.5)
        #expect(!LimitsSummary.empty.planReportsNoLimits)
    }

    @Test func passedResetIsReportedInsteadOfAStalePercentage() {
        let records = [limits("a", observedAt: noon.adding(hours: -3), fiveHour: (90, noon.adding(minutes: -1)))]

        let summary = LimitsAggregator.summarize(records, now: noon, timeZone: kyiv)

        #expect(summary.fiveHour == .resetPassed(at: noon.adding(minutes: -1)))
    }

    @Test func resetExactlyNowCountsAsPassed() {
        let records = [limits("a", fiveHour: (50, noon))]

        #expect(LimitsAggregator.summarize(records, now: noon, timeZone: kyiv).fiveHour == .resetPassed(at: noon))
    }

    @Test func costTodayAddsOnlyTodaysShareOfEachSession() {
        let records = [
            limits("overnight", cost: 7.5, day: "2026-10-13", dayStartCost: 5),
            limits("today", cost: 1.25, day: "2026-10-13", dayStartCost: 0),
            limits("yesterday", cost: 9, day: "2026-10-12", dayStartCost: 0),
        ]

        #expect(LimitsAggregator.summarize(records, now: noon, timeZone: kyiv).costToday == 3.75)
    }

    @Test func costNeverGoesNegative() {
        let records = [limits("a", cost: 1, dayStartCost: 2)]

        #expect(LimitsAggregator.summarize(records, now: noon, timeZone: kyiv).costToday == 0)
    }

    @Test func todayFollowsTheLocalTimeZone() {
        // 2026-10-13 23:30 in Kyiv is already 2026-10-14 in Tokyo.
        let lateEvening = noon.adding(hours: 11.5)

        #expect(LimitsAggregator.dayString(lateEvening, timeZone: kyiv) == "2026-10-13")
        #expect(LimitsAggregator.dayString(lateEvening, timeZone: TimeZone(identifier: "Asia/Tokyo")!) == "2026-10-14")
    }
}
