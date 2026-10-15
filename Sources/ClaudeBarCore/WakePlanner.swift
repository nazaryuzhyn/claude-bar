import Foundation

/// When the app next has to look again without a file change: a window resets, a session
/// turns unknown or hides, or old files are due for cleanup. Waking only then keeps an idle
/// app asleep instead of polling.
public enum WakePlanner {
    static let cleanupInterval: TimeInterval = 3600
    /// A reset counts as passed only once `now` is past it.
    static let resetGrace: TimeInterval = 1

    public static func nextWake(summary: LimitsSummary, rows: [SessionRow], now: Date) -> Date {
        var candidates = [now.addingTimeInterval(cleanupInterval)]
        for kind in WindowKind.allCases {
            if case .current(let reading) = summary.status(of: kind) {
                candidates.append(reading.resetsAt.addingTimeInterval(resetGrace))
            }
        }
        for row in rows {
            switch (row.state, row.freshness) {
            case (.working, .live):
                candidates.append(row.at.addingTimeInterval(SessionList.workingTurnsUnknownAfter + 1))
            case (.waiting, _), (.done, _):
                candidates.append(row.at.addingTimeInterval(SessionList.finishedHiddenAfter + 1))
            case (.working, .unknown):
                break
            }
        }
        return max(candidates.min() ?? now, now.addingTimeInterval(1))
    }
}
