import Foundation
import Testing
@testable import ClaudeBarCore

struct TextsTests {
    private let uk = Texts(.ukrainian)
    private let en = Texts(.english)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = kyiv
        return calendar
    }

    @Test(arguments: [
        (30.0, "1 хв"), (60, "1 хв"), (61, "2 хв"), (3600, "1 год"), (4320, "1 год 12 хв"),
        (86400, "1 дн"), (97200, "1 дн 3 год"),
    ])
    func duration(seconds: Double, expected: String) {
        #expect(uk.duration(seconds) == expected)
    }

    @Test(arguments: [(30, "щойно"), (120, "2 хв тому"), (10900, "3 год тому"), (180000, "2 дн тому")] as [(Double, String)])
    func ago(seconds: Double, expected: String) {
        #expect(uk.ago(noon.addingTimeInterval(-seconds), now: noon) == expected)
    }

    @Test func resetLaterToday() {
        #expect(uk.resetText(noon.adding(hours: 2.5), now: noon, calendar: calendar) == "Скинеться о 14:30, через 2 год 30 хв")
    }

    @Test func resetTomorrowWithinADay() {
        #expect(uk.resetText(noon.adding(hours: 13), now: noon, calendar: calendar) == "Скинеться завтра о 01:00, через 13 год")
    }

    @Test func resetTomorrowMoreThanADayAwayHasNoCountdown() {
        #expect(uk.resetText(noon.adding(hours: 25), now: noon, calendar: calendar) == "Скинеться завтра о 13:00")
    }

    @Test func resetLaterInTheWeek() {
        // Noon is Tuesday 2026-10-13; three days later is Friday, a week later Tuesday again.
        #expect(uk.resetText(noon.adding(hours: 69), now: noon, calendar: calendar) == "Скинеться в пт о 09:00")
        #expect(uk.resetText(noon.adding(hours: 7 * 24 - 3), now: noon, calendar: calendar) == "Скинеться у вт о 09:00")
    }

    @Test func percent() {
        #expect(Texts.percent(41.6) == "42%")
    }

    @Test func paceStatusIsAlwaysWordedByTone() {
        let ahead = Pace(reading: WindowReading(kind: .fiveHour, usedPercentage: 65, resetsAt: noon.adding(hours: 2.5), observedAt: noon), now: noon)
        let onPace = Pace(reading: WindowReading(kind: .fiveHour, usedPercentage: 50, resetsAt: noon.adding(hours: 2.5), observedAt: noon), now: noon)
        let over = Pace(reading: WindowReading(kind: .fiveHour, usedPercentage: 95, resetsAt: noon.adding(hours: 2.5), observedAt: noon), now: noon)

        #expect(uk.paceStatus(ahead) == "На 15% швидше за темп")
        #expect(uk.paceStatus(onPace) == "У межах темпу")
        #expect(uk.paceStatus(over) == "Ліміт майже вичерпано")
    }

    @Test func settingsWording() {
        #expect(uk.thresholdSetting(80) == "Попереджати, коли використано 80%")
        #expect(uk.lastHookEvent(nil, now: noon) == "Остання подія від Claude Code: ще не було")
        #expect(uk.limitsUpdated(noon.adding(minutes: -3), now: noon) == "Ліміти оновлено: 3 хв тому")
    }

    @Test func updatedLine() {
        #expect(uk.updated(nil, now: noon) == "Даних ще немає")
        #expect(uk.updated(noon.adding(minutes: -2), now: noon) == "Оновлено 2 хв тому")
    }

    @Test func sessionNotices() {
        let done = event("a", .done, cwd: "/x/web", message: "All tests pass.")
        let waiting = event("b", .waiting, cwd: "/x/api-gateway", message: "Claude needs your permission to use Bash")
        let waitingWithoutMessage = event("c", .waiting, cwd: "/x/docs")

        #expect(uk.sessionNotice(done) == NoticeText(title: "web: відповідь готова", body: "All tests pass."))
        #expect(uk.sessionNotice(waiting) == NoticeText(title: "api-gateway чекає на вас", body: "Claude needs your permission to use Bash"))
        #expect(uk.sessionNotice(waitingWithoutMessage).body == "Потрібна ваша відповідь")
    }

    @Test func thresholdNotices() {
        let fiveHour = ThresholdAlert(reading: WindowReading(kind: .fiveHour, usedPercentage: 81.6, resetsAt: noon.adding(hours: 2.5), observedAt: noon))
        let week = ThresholdAlert(reading: WindowReading(kind: .sevenDay, usedPercentage: 80, resetsAt: noon.adding(hours: 69), observedAt: noon))

        #expect(uk.thresholdNotice(fiveHour, now: noon, calendar: calendar) == NoticeText(title: "Використано 82% ліміту на 5 годин", body: "Скинеться о 14:30, через 2 год 30 хв"))
        #expect(uk.thresholdNotice(week, now: noon, calendar: calendar).title == "Використано 80% тижневого ліміту")
    }

    @Test func rowStatusAndTime() {
        let rows = SessionList.rows(from: [
            event("w", .working, at: noon.adding(minutes: -3)),
            event("d", .done, at: noon.adding(minutes: -116)),
            event("q", .waiting, at: noon.adding(minutes: -2)),
            event("u", .working, at: noon.adding(hours: -3)),
        ], now: noon)
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })

        #expect(uk.status(of: byID["w"]!) == "працює")
        #expect(uk.time(of: byID["w"]!, now: noon, calendar: calendar) == "3 хв")
        #expect(uk.status(of: byID["d"]!) == "готово")
        #expect(uk.time(of: byID["d"]!, now: noon, calendar: calendar) == "10:04")
        #expect(uk.time(of: byID["q"]!, now: noon, calendar: calendar) == "2 хв тому")
        #expect(uk.status(of: byID["u"]!) == "невідомо")
    }

    @Test func englishWording() {
        #expect(en.duration(4320) == "1 h 12 min")
        #expect(en.duration(97200) == "1 d 3 h")
        #expect(en.ago(noon.adding(minutes: -2), now: noon) == "2 min ago")
        #expect(en.resetText(noon.adding(hours: 2.5), now: noon, calendar: calendar) == "Resets at 14:30, in 2 h 30 min")
        #expect(en.resetText(noon.adding(hours: 13), now: noon, calendar: calendar) == "Resets tomorrow at 01:00, in 13 h")
        #expect(en.resetText(noon.adding(hours: 69), now: noon, calendar: calendar) == "Resets Fri at 09:00")
        #expect(en.updated(noon.adding(minutes: -2), now: noon) == "Updated 2 min ago")
        #expect(en.moreSessions(3) == "3 more")
        #expect(en.thresholdSetting(80) == "Warn when 80% is used")
    }

    @Test func englishNotices() {
        let fiveHour = ThresholdAlert(reading: WindowReading(kind: .fiveHour, usedPercentage: 81.6, resetsAt: noon.adding(hours: 2.5), observedAt: noon))
        let waiting = event("b", .waiting, cwd: "/x/api-gateway")
        let ahead = Pace(reading: WindowReading(kind: .fiveHour, usedPercentage: 65, resetsAt: noon.adding(hours: 2.5), observedAt: noon), now: noon)

        #expect(en.thresholdNotice(fiveHour, now: noon, calendar: calendar).title == "82% of the 5-hour limit used")
        #expect(en.sessionNotice(waiting) == NoticeText(title: "api-gateway is waiting for you", body: "Needs your answer"))
        #expect(en.paceStatus(ahead) == "15% ahead of pace")
    }

    @Test func menuBarDescriptionNamesTheWindowAndTheWaiting() {
        let figure = MenuBarFigure(kind: .sevenDay, percent: "14%", resetsAt: noon.adding(hours: 69))

        #expect(en.menuBarDescription(figure, waiting: 2, now: noon, calendar: calendar) == "Week: 14% used. Resets Fri at 09:00, waiting for you: 2")
        #expect(uk.menuBarDescription(nil, waiting: 0, now: noon, calendar: calendar) == "ClaudeBar")
    }

    @Test(arguments: [(["uk-UA", "en-US"], Language.ukrainian), (["uk"], .ukrainian), (["en-GB", "uk-UA"], .english), (["de-DE"], .english), ([], .english)])
    func preferredLanguageFollowsTheFirstSystemLanguage(languages: [String], expected: Language) {
        #expect(Language.preferred(languages) == expected)
    }
}

struct SoundGateTests {
    @Test func completionSoundsPauseForFiveSeconds() {
        var gate = SoundGate()

        let first = gate.allows(.done, at: noon)
        let tooSoon = gate.allows(.done, at: noon.addingTimeInterval(4.9))
        let afterPause = gate.allows(.done, at: noon.addingTimeInterval(5))

        #expect(first)
        #expect(!tooSoon)
        #expect(afterPause)
    }

    @Test func waitingSoundsAreNeverHeldBack() {
        var gate = SoundGate()
        _ = gate.allows(.done, at: noon)

        let first = gate.allows(.waiting, at: noon.addingTimeInterval(1))
        let second = gate.allows(.waiting, at: noon.addingTimeInterval(1.1))

        #expect(first)
        #expect(second)
    }

    @Test func aClockMovedBackwardsResetsTheGate() {
        var gate = SoundGate()
        _ = gate.allows(.done, at: noon)

        let afterJump = gate.allows(.done, at: noon.addingTimeInterval(-60))

        #expect(afterJump)
    }
}
