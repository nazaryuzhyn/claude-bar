import Foundation
import Testing
@testable import ClaudeBarCore

struct RecordFolderTests {
    private func event(_ session: String, _ state: String) -> String {
        #"{"session_id": "\#(session)", "state": "\#(state)", "event": "Stop", "at": 1760352000}"#
    }

    @Test func readsJSONFilesInNameOrderAndSkipsTemporaryFiles() throws {
        let folder = try TemporaryFolder()
        try folder.write("b.json", event("b", "working"))
        try folder.write("a.json", event("a", "done"))
        try folder.write(".a.json.1F2E.tmp", event("a", "waiting"))
        try folder.write("notes.txt", "not a record")
        var reader = RecordFolder<EventRecord>(url: folder.url)

        let snapshot = reader.read()

        #expect(snapshot.records.map(\.sessionID) == ["a", "b"])
        #expect(snapshot.records.map(\.state) == [.done, .working])
        #expect(snapshot.newlyFailed.isEmpty)
    }

    @Test func anImplausibleTimeIsDamage() throws {
        let folder = try TemporaryFolder()
        try folder.write("a.json", #"{"session_id": "a", "state": "done", "event": "Stop", "at": 1e19}"#)
        var reader = RecordFolder<EventRecord>(url: folder.url)

        let snapshot = reader.read()

        #expect(snapshot.records.isEmpty)
        #expect(snapshot.newlyFailed == ["a.json"])
    }

    @Test func brokenFileKeepsLastGoodRecordAndIsReportedOnce() throws {
        let folder = try TemporaryFolder()
        try folder.write("a.json", event("a", "working"))
        var reader = RecordFolder<EventRecord>(url: folder.url)
        _ = reader.read()

        try folder.write("a.json", "{\"session_id\": ")
        let first = reader.read()
        let second = reader.read()

        #expect(first.records.map(\.state) == [.working])
        #expect(first.newlyFailed == ["a.json"])
        #expect(second.records.map(\.state) == [.working])
        #expect(second.newlyFailed.isEmpty)
    }

    @Test func repairedFileIsReadAgainAndANewBreakIsReportedAgain() throws {
        let folder = try TemporaryFolder()
        try folder.write("a.json", "broken")
        var reader = RecordFolder<EventRecord>(url: folder.url)
        _ = reader.read()

        try folder.write("a.json", event("a", "done"))
        let repaired = reader.read()
        try folder.write("a.json", "broken again")
        let brokenAgain = reader.read()

        #expect(repaired.records.map(\.state) == [.done])
        #expect(repaired.newlyFailed.isEmpty)
        #expect(brokenAgain.records.map(\.state) == [.done])
        #expect(brokenAgain.newlyFailed == ["a.json"])
    }

    @Test func brokenFileWithoutHistoryYieldsNoRecord() throws {
        let folder = try TemporaryFolder()
        try folder.write("a.json", event("a", "unknown-state"))
        var reader = RecordFolder<EventRecord>(url: folder.url)

        let snapshot = reader.read()

        #expect(snapshot.records.isEmpty)
        #expect(snapshot.newlyFailed == ["a.json"])
    }

    @Test func deletedFileDisappears() throws {
        let folder = try TemporaryFolder()
        try folder.write("a.json", event("a", "done"))
        try folder.write("b.json", event("b", "done"))
        var reader = RecordFolder<EventRecord>(url: folder.url)
        _ = reader.read()

        try folder.remove("a.json")
        let snapshot = reader.read()

        #expect(snapshot.records.map(\.sessionID) == ["b"])
    }

    @Test func missingFolderReadsAsEmpty() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("claudebar-missing-\(UUID().uuidString)")
        var reader = RecordFolder<LimitsRecord>(url: missing)

        let snapshot = reader.read()

        #expect(snapshot.records.isEmpty)
        #expect(snapshot.newlyFailed.isEmpty)
    }
}
