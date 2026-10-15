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

public struct LimitsSummary: Equatable, Sendable {
    public let fiveHour: WindowStatus?
    public let sevenDay: WindowStatus?
    /// Sum of today's share of every session's estimated cost, in USD.
    public let costToday: Double
    public let lastObservedAt: Date?

    public static let empty = LimitsSummary(fiveHour: nil, sevenDay: nil, costToday: 0, lastObservedAt: nil)

    public func status(of kind: WindowKind) -> WindowStatus? {
        switch kind {
        case .fiveHour: fiveHour
        case .sevenDay: sevenDay
        }
    }
}

public enum LimitsAggregator {
    /// Limits are shared by the whole account, so a reading from any session is valid.
    public static func summarize(_ records: [LimitsRecord], now: Date, timeZone: TimeZone = .current) -> LimitsSummary {
        let today = dayString(now, timeZone: timeZone)
        let costToday = records
            .filter { $0.day == today }
            .reduce(0) { $0 + max(0, $1.cost - $1.dayStartCost) }

        return LimitsSummary(
            fiveHour: status(of: .fiveHour, in: records, now: now),
            sevenDay: status(of: .sevenDay, in: records, now: now),
            costToday: costToday,
            lastObservedAt: records.map(\.observedAt).max()
        )
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
