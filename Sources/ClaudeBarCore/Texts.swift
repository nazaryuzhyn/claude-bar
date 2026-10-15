import Foundation

public struct NoticeText: Equatable, Sendable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public enum Language: String, CaseIterable, Identifiable, Sendable {
    case ukrainian = "uk"
    case english = "en"

    public var id: String { rawValue }

    /// Each language named in itself, as a language menu shows it.
    public var name: String {
        switch self {
        case .ukrainian: "Українська"
        case .english: "English"
        }
    }

    /// Ukrainian when it leads the system's preferred languages, English otherwise.
    public static func preferred(_ languages: [String] = Locale.preferredLanguages) -> Language {
        languages.first?.hasPrefix("uk") == true ? .ukrainian : .english
    }
}

/// Every user-facing string in both languages, side by side, so wording can be tested
/// without the UI and a change to one language is never missed in the other.
public struct Texts: Equatable, Sendable {
    public let language: Language

    public init(_ language: Language) {
        self.language = language
    }

    private func pick(_ ukrainian: String, _ english: String) -> String {
        language == .ukrainian ? ukrainian : english
    }

    /// Indexed by `Calendar.component(.weekday)` − 1, which starts on Sunday. Fixed names rather
    /// than the calendar's, so a weekday never comes out in a third language.
    private var weekdays: [String] {
        pick("нд пн вт ср чт пт сб", "Sun Mon Tue Wed Thu Fri Sat").components(separatedBy: " ")
    }

    public static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    public static func clock(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    public func windowTitle(_ kind: WindowKind) -> String {
        switch kind {
        case .fiveHour: pick("5 годин", "5 hours")
        case .sevenDay: pick("Тиждень", "Week")
        }
    }

    /// Rounded up, so a reset is never announced as "in 0 min" before it happens.
    public func duration(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int((interval / 60).rounded(.up)))
        let (min, hour, day) = (pick("хв", "min"), pick("год", "h"), pick("дн", "d"))
        if minutes < 60 { return "\(minutes) \(min)" }
        let hours = minutes / 60
        let restMinutes = minutes % 60
        if hours < 24 { return restMinutes == 0 ? "\(hours) \(hour)" : "\(hours) \(hour) \(restMinutes) \(min)" }
        let days = hours / 24
        let restHours = hours % 24
        return restHours == 0 ? "\(days) \(day)" : "\(days) \(day) \(restHours) \(hour)"
    }

    public func ago(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return pick("щойно", "just now") }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return pick("\(minutes) хв тому", "\(minutes) min ago") }
        let hours = minutes / 60
        if hours < 24 { return pick("\(hours) год тому", "\(hours) h ago") }
        return pick("\(hours / 24) дн тому", "\(hours / 24) d ago")
    }

    public func resetText(_ resetsAt: Date, now: Date, calendar: Calendar) -> String {
        let time = Self.clock(resetsAt, calendar: calendar)
        let remaining = resetsAt.timeIntervalSince(now)
        if calendar.isDate(resetsAt, inSameDayAs: now) {
            return pick("Скинеться о \(time), через \(duration(remaining))", "Resets at \(time), in \(duration(remaining))")
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(resetsAt, inSameDayAs: tomorrow) {
            return remaining < 24 * 3600
                ? pick("Скинеться завтра о \(time), через \(duration(remaining))", "Resets tomorrow at \(time), in \(duration(remaining))")
                : pick("Скинеться завтра о \(time)", "Resets tomorrow at \(time)")
        }
        let day = weekdays[calendar.component(.weekday, from: resetsAt) - 1]
        let preposition = day.hasPrefix("в") ? "у" : "в"
        return pick("Скинеться \(preposition) \(day) о \(time)", "Resets \(day) at \(time)")
    }

    public var resetPassed: String { pick("Вікно скинулося, чекаю нових даних", "Window reset, waiting for new data") }
    public var noLimits: String { pick("Ліміти з'являться після першої відповіді Claude.", "Limits appear after Claude's first reply.") }
    public var noSessions: String { pick("Сесій немає. Запустіть claude у терміналі.", "No sessions. Run claude in a terminal.") }
    public var waitingHeader: String { pick("Чекають на вас", "Waiting for you") }

    public func moreSessions(_ count: Int) -> String {
        pick("Ще \(count)", "\(count) more")
    }

    /// Next to the big percentage, which alone could read as what is left.
    public var usedCaption: String { pick("використано", "used") }
    public var paceHelp: String { pick("Риска показує, скільки часу цього вікна вже минуло", "The tick shows how much of this window's time has passed") }

    /// Always shown, so the tick on the bar always has words next to it.
    public func paceStatus(_ pace: Pace) -> String {
        switch pace.tone {
        case .normal: pick("У межах темпу", "On pace")
        case .signal: pick("На \(Int(pace.delta.rounded()))% швидше за темп", "\(Int(pace.delta.rounded()))% ahead of pace")
        case .over: pick("Ліміт майже вичерпано", "Limit almost used up")
        }
    }

    public func updated(_ date: Date?, now: Date) -> String {
        guard let date else { return pick("Даних ще немає", "No data yet") }
        return pick("Оновлено \(ago(date, now: now))", "Updated \(ago(date, now: now))")
    }

    public func status(of row: SessionRow) -> String {
        if row.freshness == .unknown { return pick("невідомо", "unknown") }
        switch row.state {
        case .working: return pick("працює", "working")
        case .waiting: return pick("чекає на вас", "waiting for you")
        case .done: return pick("готово", "done")
        }
    }

    /// Working: how long since the last event; done: when it finished; waiting: how long it has waited.
    public func time(of row: SessionRow, now: Date, calendar: Calendar) -> String {
        switch row.state {
        case .working: duration(now.timeIntervalSince(row.at))
        case .done: Self.clock(row.at, calendar: calendar)
        case .waiting: ago(row.at, now: now)
        }
    }

    /// What VoiceOver reads for the menu bar label.
    public func menuBarDescription(_ figure: MenuBarFigure?, waiting: Int, now: Date, calendar: Calendar) -> String {
        var parts: [String] = []
        if let figure {
            let reset = resetText(figure.resetsAt, now: now, calendar: calendar)
            parts.append(pick("\(windowTitle(figure.kind)): використано \(figure.percent). \(reset)", "\(windowTitle(figure.kind)): \(figure.percent) used. \(reset)"))
        }
        if waiting > 0 {
            parts.append(pick("чекають на вас: \(waiting)", "waiting for you: \(waiting)"))
        }
        return parts.isEmpty ? "ClaudeBar" : parts.joined(separator: ", ")
    }

    // MARK: Panel actions and settings

    public var settings: String { pick("Налаштування", "Settings") }
    public var quit: String { pick("Вийти", "Quit") }
    public var done: String { pick("Готово", "Done") }
    public var sound: String { pick("Звук", "Sound") }
    public var banners: String { pick("Банери", "Banners") }
    public var bannersNote: String { pick("Не з'являються, поки програма сесії на передньому плані. Звук лишається.", "Hidden while the session's app is in front. The sound still plays.") }
    public var bannersDenied: String { pick("macOS забороняє банери для ClaudeBar.", "macOS blocks banners for ClaudeBar.") }
    public var openSystemSettings: String { pick("Відкрити системні налаштування", "Open System Settings") }
    public var launchAtLogin: String { pick("Запускати під час входу", "Launch at login") }
    public var languageSetting: String { pick("Мова", "Language") }
    public var testNotice: String { pick("Перевірити звук і банер", "Test sound and banner") }

    public func thresholdSetting(_ percent: Double) -> String {
        pick("Попереджати, коли використано \(Self.percent(percent))", "Warn when \(Self.percent(percent)) is used")
    }

    public func lastHookEvent(_ date: Date?, now: Date) -> String {
        let when = date.map { ago($0, now: now) } ?? pick("ще не було", "none yet")
        return pick("Остання подія від Claude Code: \(when)", "Last Claude Code event: \(when)")
    }

    public func limitsUpdated(_ date: Date?, now: Date) -> String {
        let when = date.map { ago($0, now: now) } ?? pick("ще не було", "not yet")
        return pick("Ліміти оновлено: \(when)", "Limits updated: \(when)")
    }

    public func loginError(_ error: Error) -> String {
        pick("Не вдалося змінити запуск під час входу: \(error.localizedDescription)", "Could not change launch at login: \(error.localizedDescription)")
    }

    // MARK: Notifications

    public var sampleNotice: NoticeText {
        NoticeText(title: "ClaudeBar", body: pick("Так виглядатиме сповіщення про готову відповідь", "This is how a finished reply is announced"))
    }

    public func sessionNotice(_ record: EventRecord, name claudeName: String? = nil) -> NoticeText {
        let name = SessionList.displayName(of: record, name: claudeName)
        switch record.state {
        case .done: return NoticeText(title: pick("\(name): відповідь готова", "\(name): reply ready"), body: record.message ?? "")
        case .waiting: return NoticeText(title: pick("\(name) чекає на вас", "\(name) is waiting for you"), body: record.message ?? pick("Потрібна ваша відповідь", "Needs your answer"))
        case .working: return NoticeText(title: name, body: "")
        }
    }

    public func thresholdNotice(_ alert: ThresholdAlert, now: Date, calendar: Calendar) -> NoticeText {
        let reading = alert.reading
        let used = Self.percent(reading.usedPercentage)
        let title = switch reading.kind {
        case .fiveHour: pick("Використано \(used) ліміту на 5 годин", "\(used) of the 5-hour limit used")
        case .sevenDay: pick("Використано \(used) тижневого ліміту", "\(used) of the weekly limit used")
        }
        return NoticeText(title: title, body: resetText(reading.resetsAt, now: now, calendar: calendar))
    }
}
