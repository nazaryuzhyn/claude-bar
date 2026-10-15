import Foundation
import Testing
@testable import ClaudeBarCore

struct RecordsTests {
    private func decode<Record: Decodable>(_ type: Record.Type, _ json: String) throws -> Record {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(type, from: Data(json.utf8))
    }

    @Test func limitsRecordWithBothWindows() throws {
        let record = try decode(LimitsRecord.self, """
        {"session_id": "abc", "observed_at": 1760352000,
         "rate_limits": {"five_hour": {"used_percentage": 23.5, "resets_at": 1760360000},
                         "seven_day": {"used_percentage": 41.2, "resets_at": 1760800000}},
         "cost": 1.234, "day": "2026-10-13", "day_start_cost": 0.5}
        """)

        #expect(record.sessionID == "abc")
        #expect(record.observedAt == Date(timeIntervalSince1970: 1_760_352_000))
        #expect(record.rateLimits?.fiveHour == LimitWindow(usedPercentage: 23.5, resetsAt: Date(timeIntervalSince1970: 1_760_360_000)))
        #expect(record.rateLimits?.sevenDay?.usedPercentage == 41.2)
        #expect(record.cost == 1.234)
        #expect(record.day == "2026-10-13")
        #expect(record.dayStartCost == 0.5)
    }

    @Test func limitsRecordWithoutRateLimits() throws {
        let record = try decode(LimitsRecord.self, """
        {"session_id": "abc", "observed_at": 1760352000, "cost": 0, "day": "2026-10-13", "day_start_cost": 0}
        """)

        #expect(record.rateLimits == nil)
        #expect(record.configDir == nil)
    }

    @Test func limitsRecordNamesItsProfile() throws {
        let record = try decode(LimitsRecord.self, """
        {"session_id": "abc", "observed_at": 1760352000, "cost": 0, "day": "2026-10-13", "day_start_cost": 0,
         "config_dir": "/Users/me/.claude-work"}
        """)

        #expect(record.configDir == "/Users/me/.claude-work")
    }

    @Test func limitsRecordKnowsWhetherClaudeAnswered() throws {
        let record = try decode(LimitsRecord.self, """
        {"session_id": "abc", "observed_at": 1760352000, "cost": 0, "day": "2026-10-13", "day_start_cost": 0, "answered": true}
        """)

        #expect(record.answered == true)
    }

    @Test func redactedDropsWhatClaudeWroteOrTitled() {
        let record = event("a", .done, cwd: "/x/web", title: "Secret plan", message: "Secret answer").redacted

        #expect(record.title == nil)
        #expect(record.message == nil)
        #expect(SessionList.displayName(of: record) == "web")
    }

    @Test func limitsRecordWithOneWindow() throws {
        let record = try decode(LimitsRecord.self, """
        {"session_id": "abc", "observed_at": 1760352000,
         "rate_limits": {"five_hour": {"used_percentage": 5, "resets_at": 1760360000}},
         "cost": 0, "day": "2026-10-13", "day_start_cost": 0}
        """)

        #expect(record.rateLimits?.fiveHour?.usedPercentage == 5)
        #expect(record.rateLimits?.sevenDay == nil)
    }

    @Test func eventRecordWithOptionalFieldsAbsent() throws {
        let record = try decode(EventRecord.self, """
        {"session_id": "abc", "state": "done", "event": "Stop", "at": 1760352000}
        """)

        #expect(record.state == .done)
        #expect(record.cwd == nil)
        #expect(record.title == nil)
        #expect(record.message == nil)
        #expect(record.at == Date(timeIntervalSince1970: 1_760_352_000))
    }

    @Test func eventRecordRejectsUnknownState() {
        #expect(throws: DecodingError.self) {
            try decode(EventRecord.self, """
            {"session_id": "abc", "state": "thinking", "event": "Stop", "at": 1760352000}
            """)
        }
    }
}
