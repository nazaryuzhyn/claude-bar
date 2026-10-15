import Foundation
import Testing
@testable import ClaudeBarCore

struct SessionListTests {
    @Test func waitingFirstThenWorkingThenDoneNewestFirst() {
        let records = [
            event("done-old", .done, at: noon.adding(minutes: -30)),
            event("working", .working, at: noon.adding(minutes: -1)),
            event("done-new", .done, at: noon.adding(minutes: -2)),
            event("waiting", .waiting, at: noon.adding(minutes: -40)),
        ]

        let rows = SessionList.rows(from: records, now: noon)

        #expect(rows.map(\.id) == ["waiting", "working", "done-new", "done-old"])
    }

    @Test func aWorkingSessionQuietForOverTwoHoursIsUnknown() {
        let rows = SessionList.rows(from: [
            event("quiet", .working, at: noon.adding(hours: -2).adding(minutes: -1)),
            event("busy", .working, at: noon.adding(hours: -2)),
        ], now: noon)

        #expect(rows.first { $0.id == "quiet" }?.freshness == .unknown)
        #expect(rows.first { $0.id == "busy" }?.freshness == .live)
    }

    @Test func finishedSessionsHideAfterTwelveHours() {
        let rows = SessionList.rows(from: [
            event("old-done", .done, at: noon.adding(hours: -12).adding(minutes: -1)),
            event("old-waiting", .waiting, at: noon.adding(hours: -13)),
            event("recent", .done, at: noon.adding(hours: -12)),
        ], now: noon)

        #expect(rows.map(\.id) == ["recent"])
    }

    @Test func panelKeepsEveryWaitingSessionAndTheFiveMostRecentOthers() {
        var records = (0..<7).map { event("s\($0)", $0.isMultiple(of: 2) ? .done : .working, at: noon.adding(minutes: Double(-$0))) }
        records += [event("w1", .waiting, at: noon.adding(minutes: -50)), event("w2", .waiting, at: noon.adding(minutes: -60))]

        let panel = SessionList.panel(from: SessionList.rows(from: records, now: noon))

        #expect(panel.waiting.map(\.id) == ["w1", "w2"])
        #expect(panel.recent.map(\.id) == ["s0", "s1", "s2", "s3", "s4"])
        #expect(panel.moreCount == 2)
    }

    @Test func panelWithFewSessionsHasNothingMore() {
        let panel = SessionList.panel(from: SessionList.rows(from: [event("a", .working), event("b", .done)], now: noon))

        #expect(panel.recent.count == 2)
        #expect(panel.moreCount == 0)
    }

    @Test func claudeCodesOwnNameComesFirst() {
        let names = SessionList.names(from: [
            limits("a", sessionName: "Fix flaky login test"),
            limits("b", sessionName: ""),
            limits("c"),
        ])
        let rows = SessionList.rows(from: [
            event("a", .working, cwd: "/x/web", title: "Started as this"),
            event("b", .working, cwd: "/x/docs"),
            event("c", .working, cwd: "/x/api"),
        ], now: noon, names: names)

        #expect(names == ["a": "Fix flaky login test"])
        #expect(Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.name) }) == ["a": "Fix flaky login test", "b": "docs", "c": "api"])
        #expect(Texts(.ukrainian).sessionNotice(event("a", .done, cwd: "/x/web"), name: names["a"]).title == "Fix flaky login test: відповідь готова")
    }

    @Test func nameIsTitleThenFolderThenShortID() {
        #expect(SessionList.displayName(of: event("a", .done, cwd: "/x/api-gateway", title: "Add rate limiting")) == "Add rate limiting")
        #expect(SessionList.displayName(of: event("a", .done, cwd: "/x/api-gateway", title: "")) == "api-gateway")
        #expect(SessionList.displayName(of: event("0123456789abcdef", .done, cwd: nil)) == "01234567")
    }
}

struct FolderCleanupTests {
    private func age(_ folder: TemporaryFolder, _ name: String, hours: Double) throws {
        try FileManager.default.setAttributes([.modificationDate: noon.adding(hours: -hours)],
                                              ofItemAtPath: folder.url.appendingPathComponent(name).path)
    }

    @Test func removesOldRecordsAndAbandonedTemporariesOnly() throws {
        let folder = try TemporaryFolder()
        for name in ["old.json", "fresh.json", ".old.json.a1B2c3", ".fresh.json.d4E5f6", "notes.txt"] {
            try folder.write(name, "{}")
        }
        try age(folder, "old.json", hours: 49)
        try age(folder, "fresh.json", hours: 47)
        try age(folder, ".old.json.a1B2c3", hours: 2)
        try age(folder, ".fresh.json.d4E5f6", hours: 0.5)
        try age(folder, "notes.txt", hours: 100)

        let removed = FolderCleanup.removeExpired(in: folder.url, now: noon)

        #expect(removed == [".old.json.a1B2c3", "old.json"])
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.url.path).sorted()
        #expect(left == [".fresh.json.d4E5f6", "fresh.json", "notes.txt"])
    }
}
