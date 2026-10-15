import Foundation

public enum SessionState: String, Decodable, Sendable {
    case working
    case waiting
    case done
}

public struct LimitWindow: Decodable, Sendable, Equatable {
    /// 0–100, the share of the window already used.
    public let usedPercentage: Double
    public let resetsAt: Date

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }
}

public struct RateLimits: Decodable, Sendable, Equatable {
    public let fiveHour: LimitWindow?
    public let sevenDay: LimitWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

/// A session's latest status line reading, written by the bridge to `limits/<session_id>.json`.
public struct LimitsRecord: Decodable, Sendable, Equatable {
    public let sessionID: String
    public let observedAt: Date
    public let rateLimits: RateLimits?
    /// Claude Code's list-price estimate in USD, not a billed amount.
    public let cost: Double
    /// Local calendar day of `observedAt`, `YYYY-MM-DD`.
    public let day: String
    /// `cost` when `day` began, so a session running past midnight adds only today's share.
    public let dayStartCost: Double
    /// The name Claude Code shows for the session; absent until one is set or generated.
    public let sessionName: String?
    /// `CLAUDE_CONFIG_DIR` of the session when set: another profile, often another account.
    public var configDir: String? = nil
    /// Claude Code has had an API response in this session; rate limits never come before one.
    public var answered: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case observedAt = "observed_at"
        case rateLimits = "rate_limits"
        case cost
        case day
        case dayStartCost = "day_start_cost"
        case sessionName = "session_name"
        case configDir = "config_dir"
        case answered
    }
}

/// A session's state after its latest hook event, written by the hook to `events/<session_id>.json`.
public struct EventRecord: Decodable, Sendable, Equatable {
    public let sessionID: String
    public let state: SessionState
    public let cwd: String?
    public let title: String?
    public let message: String?
    /// The hook event that produced this state, kept for diagnosis.
    public let event: String
    public let at: Date
    /// Bundle id of the app the session runs in, such as `com.jetbrains.PhpStorm`.
    public let host: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case state
        case cwd
        case title
        case message
        case event
        case at
        case host
    }
}

extension EventRecord {
    /// Without anything Claude wrote or titled, for private mode: the folder then names the session.
    public var redacted: EventRecord {
        EventRecord(sessionID: sessionID, state: state, cwd: cwd, title: nil, message: nil, event: event, at: at, host: host)
    }
}
