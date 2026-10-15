import Foundation
@testable import ClaudeBarCore

/// 2026-10-13 12:00:00 in Kyiv (UTC+3).
let noon = Date(timeIntervalSince1970: 1_791_882_000)
let kyiv = TimeZone(identifier: "Europe/Kyiv")!

func limits(
    _ session: String,
    observedAt: Date = noon,
    fiveHour: (Double, Date)? = nil,
    sevenDay: (Double, Date)? = nil,
    cost: Double = 0,
    day: String = "2026-10-13",
    dayStartCost: Double = 0,
    sessionName: String? = nil
) -> LimitsRecord {
    let rateLimits: RateLimits? = fiveHour == nil && sevenDay == nil ? nil : RateLimits(
        fiveHour: fiveHour.map { LimitWindow(usedPercentage: $0.0, resetsAt: $0.1) },
        sevenDay: sevenDay.map { LimitWindow(usedPercentage: $0.0, resetsAt: $0.1) }
    )
    return LimitsRecord(sessionID: session, observedAt: observedAt, rateLimits: rateLimits, cost: cost, day: day,
                        dayStartCost: dayStartCost, sessionName: sessionName)
}

func event(
    _ session: String,
    _ state: SessionState,
    at: Date = noon,
    cwd: String? = "/Users/me/Projects/\(UUID().uuidString.prefix(4))",
    title: String? = nil,
    message: String? = nil,
    host: String? = nil
) -> EventRecord {
    EventRecord(sessionID: session, state: state, cwd: cwd, title: title, message: message, event: "Test", at: at, host: host)
}

extension Date {
    func adding(minutes: Double) -> Date { addingTimeInterval(minutes * 60) }
    func adding(hours: Double) -> Date { addingTimeInterval(hours * 3600) }
}
