import Foundation

public enum WindowKind: String, CaseIterable, Sendable {
    case fiveHour
    case sevenDay

    public var length: TimeInterval {
        switch self {
        case .fiveHour: 5 * 3600
        case .sevenDay: 7 * 24 * 3600
        }
    }

    /// Reset times can shift slightly between readings, so two of them closer than this belong
    /// to one window; the next window resets hours later.
    static let sameWindowTolerance: TimeInterval = 3600
}

public struct WindowReading: Equatable, Sendable {
    public let kind: WindowKind
    public let usedPercentage: Double
    public let resetsAt: Date
    public let observedAt: Date
}

public enum WindowStatus: Equatable, Sendable {
    case current(WindowReading)
    /// The newest reading's reset time has passed and no reading of the next window has arrived yet.
    case resetPassed(at: Date)
}

/// One Claude Code profile's limits. Profiles (`CLAUDE_CONFIG_DIR`) may be different accounts,
/// so each gets its own summary and their figures never mix.
public struct LimitsSummary: Equatable, Sendable, Identifiable {
    public let fiveHour: WindowStatus?
    public let sevenDay: WindowStatus?
    /// Sum of today's share of every session's estimated cost, in USD.
    public let costToday: Double
    public let lastObservedAt: Date?
    /// The profile's `CLAUDE_CONFIG_DIR`, `nil` for the default one.
    public var configDir: String? = nil
    /// The profile's name, set only when there is more than one profile to tell apart.
    public var profile: String? = nil
    /// Claude Code has answered in at least one of the profile's sessions. Limits arrive only
    /// after that, so before it their absence says nothing about the plan.
    public var answered = false

    public var id: String { configDir ?? "" }

    /// Claude Code answered but sent no limits: the plan does not report them.
    public var planReportsNoLimits: Bool {
        fiveHour == nil && sevenDay == nil && answered
    }

    public static let empty = LimitsSummary(fiveHour: nil, sevenDay: nil, costToday: 0, lastObservedAt: nil)

    public func status(of kind: WindowKind) -> WindowStatus? {
        switch kind {
        case .fiveHour: fiveHour
        case .sevenDay: sevenDay
        }
    }
}

public enum LimitsAggregator {
    /// One summary per profile, the default one first; a profile is named only when there are several.
    public static func summarizeProfiles(_ records: [LimitsRecord], now: Date, timeZone: TimeZone = .current) -> [LimitsSummary] {
        let groups = Dictionary(grouping: records, by: \.configDir)
        let configDirs = groups.keys.sorted { ($0 ?? "") < ($1 ?? "") }
        return configDirs.map { configDir in
            var summary = summarize(groups[configDir] ?? [], now: now, timeZone: timeZone)
            summary.configDir = configDir
            summary.profile = groups.count > 1 ? profileName(configDir) : nil
            return summary
        }
    }

    /// Limits are shared by an account, so a reading from any of its sessions is valid.
    /// Expects the records of one profile.
    public static func summarize(_ records: [LimitsRecord], now: Date, timeZone: TimeZone = .current) -> LimitsSummary {
        let today = dayString(now, timeZone: timeZone)
        let costToday = records
            .filter { $0.day == today }
            .reduce(0) { $0 + max(0, $1.cost - $1.dayStartCost) }

        return LimitsSummary(
            fiveHour: status(of: .fiveHour, in: records, now: now),
            sevenDay: status(of: .sevenDay, in: records, now: now),
            costToday: costToday,
            lastObservedAt: records.map(\.observedAt).max(),
            answered: records.contains { $0.answered == true }
        )
    }

    /// The most urgent figure across profiles: the window with the largest used share.
    public static func menuBarFigure(of summaries: [LimitsSummary]) -> MenuBarFigure? {
        summaries
            .compactMap { summary in summary.menuBarReading.map { (summary, $0) } }
            .max { $0.1.usedPercentage < $1.1.usedPercentage }
            .flatMap { summary, _ in summary.menuBarFigure }
    }

    /// The folder's own name, as people tell profiles apart; the default one is `.claude`. A
    /// `.claude` folder elsewhere keeps its parent, so it does not read as the default one.
    static func profileName(_ configDir: String?) -> String {
        guard let configDir, !configDir.isEmpty else { return ".claude" }
        let url = URL(fileURLWithPath: configDir)
        guard url.lastPathComponent == ".claude" else { return url.lastPathComponent }
        return "\(url.deletingLastPathComponent().lastPathComponent)/.claude"
    }

    /// The bridge writes `day` with `date +%F`, the local calendar day.
    static func dayString(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Usage only grows within a window, but a session's file can be rewritten later with the
    /// figures that session got earlier. So among the readings of the latest window the highest wins.
    private static func status(of kind: WindowKind, in records: [LimitsRecord], now: Date) -> WindowStatus? {
        let readings = records.compactMap { record -> WindowReading? in
            guard let window = window(kind, of: record) else { return nil }
            let used = min(max(window.usedPercentage, 0), 100)
            return WindowReading(kind: kind, usedPercentage: used, resetsAt: window.resetsAt, observedAt: record.observedAt)
        }
        guard let latestReset = readings.map(\.resetsAt).max(),
              let best = readings
                  .filter({ latestReset.timeIntervalSince($0.resetsAt) < WindowKind.sameWindowTolerance })
                  .max(by: { ($0.usedPercentage, $0.observedAt) < ($1.usedPercentage, $1.observedAt) })
        else { return nil }
        return best.resetsAt <= now ? .resetPassed(at: best.resetsAt) : .current(best)
    }

    private static func window(_ kind: WindowKind, of record: LimitsRecord) -> LimitWindow? {
        switch kind {
        case .fiveHour: record.rateLimits?.fiveHour
        case .sevenDay: record.rateLimits?.sevenDay
        }
    }
}
