import Foundation

/// Finds the sessions that just finished or started waiting.
///
/// The first read only records a baseline, so launching the app replays nothing.
/// A session first seen after that is announced when it already waits or has finished,
/// unless its event is older than `firstSeenFreshness`.
public struct TransitionDetector: Sendable {
    private var seen: [String: EventRecord] = [:]
    private var hasBaseline = false

    /// An old record first seen now is old news: the folder was emptied and refilled, for one,
    /// which would otherwise replay every finished session.
    static let firstSeenFreshness: TimeInterval = 300

    public init() {}

    public mutating func notices(in records: [EventRecord], now: Date) -> [EventRecord] {
        defer {
            seen = Dictionary(records.map { ($0.sessionID, $0) }, uniquingKeysWith: { _, last in last })
            hasBaseline = true
        }
        guard hasBaseline else { return [] }
        return records.filter { record in
            guard record.state == .done || record.state == .waiting else { return false }
            guard let previous = seen[record.sessionID] else {
                return now.timeIntervalSince(record.at) < Self.firstSeenFreshness
            }
            return previous.state != record.state || record.at > previous.at
        }
    }
}

public struct ThresholdAlert: Equatable, Sendable {
    public let reading: WindowReading
    /// Named only when there are several profiles.
    public var profile: String? = nil
    public var configDir: String? = nil
}

/// One alert per window of each profile (see `WindowKind.sameWindowTolerance`).
public struct ThresholdTracker: Sendable {
    /// Reset time of the last alerted window, by `key(_:configDir:)`.
    public private(set) var alerted: [String: Date]

    public init(alerted: [String: Date] = [:]) {
        self.alerted = alerted
    }

    /// By the profile's full path, which a display name cannot stand in for; the kind alone for
    /// the default profile, which keeps alerts stored before profiles existed.
    public static func key(_ kind: WindowKind, configDir: String?) -> String {
        configDir.map { "\(kind.rawValue)@\($0)" } ?? kind.rawValue
    }

    public mutating func alerts(for summary: LimitsSummary, threshold: Double) -> [ThresholdAlert] {
        WindowKind.allCases.compactMap { kind in
            guard case .current(let reading) = summary.status(of: kind), reading.usedPercentage >= threshold else { return nil }
            let key = Self.key(kind, configDir: summary.configDir)
            if let previous = alerted[key], abs(previous.timeIntervalSince(reading.resetsAt)) < WindowKind.sameWindowTolerance {
                return nil
            }
            alerted[key] = reading.resetsAt
            return ThresholdAlert(reading: reading, profile: summary.profile, configDir: summary.configDir)
        }
    }
}
