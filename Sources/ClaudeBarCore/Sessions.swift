import Foundation

public enum SessionFreshness: Equatable, Sendable {
    case live
    /// A working session with no events for a long time: it may have died without `SessionEnd`.
    case unknown
}

public struct SessionRow: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let state: SessionState
    public let freshness: SessionFreshness
    public let message: String?
    public let at: Date
}

/// What the panel lists: every waiting session, then the most recently active of the rest.
public struct PanelSessions: Equatable, Sendable {
    public let waiting: [SessionRow]
    public let recent: [SessionRow]
    /// Sessions left out of `recent` by the limit.
    public let moreCount: Int
}

public enum SessionList {
    static let workingTurnsUnknownAfter: TimeInterval = 2 * 3600
    static let finishedHiddenAfter: TimeInterval = 12 * 3600
    public static let recentLimit = 5

    /// Waiting sessions are never cut: each one asks for the user.
    public static func panel(from rows: [SessionRow], limit: Int = recentLimit) -> PanelSessions {
        let others = rows.filter { $0.state != .waiting }.sorted { $0.at > $1.at }
        return PanelSessions(
            waiting: rows.filter { $0.state == .waiting },
            recent: Array(others.prefix(limit)),
            moreCount: max(0, others.count - limit)
        )
    }

    /// Waiting sessions first, then working, then done; the newest first within each group.
    /// `names` maps a session id to the name Claude Code shows for it (from the status line).
    public static func rows(from records: [EventRecord], now: Date, names: [String: String] = [:]) -> [SessionRow] {
        records
            .compactMap { row(for: $0, name: names[$0.sessionID], now: now) }
            .sorted { lhs, rhs in
                lhs.state.order == rhs.state.order ? lhs.at > rhs.at : lhs.state.order < rhs.state.order
            }
    }

    /// Claude Code's own name first, so a session reads the same here and there; the folder last.
    public static func displayName(of record: EventRecord, name: String? = nil) -> String {
        if let name, !name.isEmpty { return name }
        if let title = record.title, !title.isEmpty { return title }
        if let cwd = record.cwd, !cwd.isEmpty { return URL(fileURLWithPath: cwd).lastPathComponent }
        return String(record.sessionID.prefix(8))
    }

    /// Session id to the name Claude Code shows, from the status line readings.
    public static func names(from limits: [LimitsRecord]) -> [String: String] {
        var names: [String: String] = [:]
        for record in limits {
            if let name = record.sessionName, !name.isEmpty {
                names[record.sessionID] = name
            }
        }
        return names
    }

    private static func row(for record: EventRecord, name: String?, now: Date) -> SessionRow? {
        let quiet = now.timeIntervalSince(record.at)
        let freshness: SessionFreshness
        switch record.state {
        case .working:
            freshness = quiet > workingTurnsUnknownAfter ? .unknown : .live
        case .waiting, .done:
            if quiet > finishedHiddenAfter { return nil }
            freshness = .live
        }
        return SessionRow(
            id: record.sessionID,
            name: displayName(of: record, name: name),
            state: record.state,
            freshness: freshness,
            message: record.message,
            at: record.at
        )
    }
}

private extension SessionState {
    var order: Int {
        switch self {
        case .waiting: 0
        case .working: 1
        case .done: 2
        }
    }
}

public enum FolderCleanup {
    static let recordExpiry: TimeInterval = 48 * 3600
    /// Hidden files are a writer's temporaries, left behind when Claude Code cancels the writer before its rename.
    static let temporaryExpiry: TimeInterval = 3600

    /// Removes records untouched for two days and abandoned temporaries; returns the removed file names.
    @discardableResult
    public static func removeExpired(in folder: URL, now: Date) -> [String] {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: folder.path)) ?? []
        var removed: [String] = []
        for name in names.sorted() {
            guard let expiry = expiry(of: name) else { continue }
            let url = folder.appendingPathComponent(name)
            guard let modified = (try? manager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
                  now.timeIntervalSince(modified) > expiry else { continue }
            if (try? manager.removeItem(at: url)) != nil {
                removed.append(name)
            }
        }
        return removed
    }

    private static func expiry(of name: String) -> TimeInterval? {
        if name.hasPrefix(".") { return temporaryExpiry }
        if name.hasSuffix(".json") { return recordExpiry }
        return nil
    }
}
