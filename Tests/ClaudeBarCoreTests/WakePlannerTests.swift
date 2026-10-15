import Foundation
import Testing
@testable import ClaudeBarCore

struct WakePlannerTests {
    private func reading(_ kind: WindowKind, resetsIn hours: Double) -> WindowReading {
        WindowReading(kind: kind, usedPercentage: 40, resetsAt: noon.adding(hours: hours), observedAt: noon)
    }

    @Test func idleAppWakesHourlyForCleanup() {
        #expect(WakePlanner.nextWake(summary: .empty, rows: [], now: noon) == noon.adding(hours: 1))
    }

    @Test func wakesJustAfterTheNearestReset() {
        let summary = LimitsSummary(
            fiveHour: .current(reading(.fiveHour, resetsIn: 0.5)),
            sevenDay: .current(reading(.sevenDay, resetsIn: 30)),
            costToday: 0,
            lastObservedAt: noon
        )

        #expect(WakePlanner.nextWake(summary: summary, rows: [], now: noon) == noon.adding(minutes: 30).addingTimeInterval(1))
    }

    @Test func wakesWhenAWorkingSessionTurnsUnknown() {
        let rows = SessionList.rows(from: [event("a", .working, at: noon.adding(hours: -1.5))], now: noon)

        #expect(WakePlanner.nextWake(summary: .empty, rows: rows, now: noon) == noon.adding(minutes: 30).addingTimeInterval(1))
    }

    @Test func wakesWhenAFinishedSessionHides() {
        let rows = SessionList.rows(from: [event("a", .done, at: noon.adding(hours: -11.75))], now: noon)

        #expect(WakePlanner.nextWake(summary: .empty, rows: rows, now: noon) == noon.adding(minutes: 15).addingTimeInterval(1))
    }

    @Test func passedResetsAndUnknownSessionsAddNoWake() {
        let summary = LimitsSummary(fiveHour: .resetPassed(at: noon.adding(minutes: -5)), sevenDay: nil, costToday: 0, lastObservedAt: noon)
        let rows = SessionList.rows(from: [event("a", .working, at: noon.adding(hours: -3))], now: noon)

        #expect(WakePlanner.nextWake(summary: summary, rows: rows, now: noon) == noon.adding(hours: 1))
    }

    @Test func neverSchedulesInThePast() {
        let summary = LimitsSummary(fiveHour: .current(reading(.fiveHour, resetsIn: -0.001)), sevenDay: nil, costToday: 0, lastObservedAt: noon)

        #expect(WakePlanner.nextWake(summary: summary, rows: [], now: noon) == noon.addingTimeInterval(1))
    }
}

struct NoticePolicyTests {
    @Test func noBannerWhileTheSessionsAppIsInFront() {
        #expect(!NoticePolicy.showsBanner(host: "com.jetbrains.PhpStorm", frontmost: "com.jetbrains.PhpStorm"))
        #expect(NoticePolicy.showsBanner(host: "com.jetbrains.PhpStorm", frontmost: "com.google.Chrome"))
    }

    @Test func unknownHostOrFrontAppShowsTheBanner() {
        #expect(NoticePolicy.showsBanner(host: nil, frontmost: "com.jetbrains.PhpStorm"))
        #expect(NoticePolicy.showsBanner(host: "com.jetbrains.PhpStorm", frontmost: nil))
    }
}
