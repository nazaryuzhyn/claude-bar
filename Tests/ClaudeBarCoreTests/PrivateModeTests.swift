import Foundation
import Testing
@testable import ClaudeBarCore

struct PrivateModeTests {
    @Test func switchingOnLeavesAMarkerAndStripsStoredTexts() throws {
        let events = try TemporaryFolder()
        let limits = try TemporaryFolder()
        try events.write("a.json", #"{"session_id":"a","state":"done","event":"Stop","at":1760352000,"cwd":"/x/web","title":"Secret plan","message":"Secret answer"}"#)
        try limits.write("a.json", #"{"session_id":"a","observed_at":1760352000,"cost":1,"day":"2026-10-13","day_start_cost":0,"session_name":"Secret plan"}"#)
        try events.write("notes.txt", "Secret plan")

        PrivateMode.apply(true, events: events.url, limits: limits.url)

        let event = try String(contentsOf: events.url.appendingPathComponent("a.json"), encoding: .utf8)
        let limit = try String(contentsOf: limits.url.appendingPathComponent("a.json"), encoding: .utf8)
        let marker = events.url.appendingPathComponent(PrivateMode.markerName)
        #expect(FileManager.default.fileExists(atPath: marker.path))
        #expect(!event.contains("Secret"))
        #expect(event.contains("web"))
        #expect(!limit.contains("Secret"))
        #expect(try String(contentsOf: events.url.appendingPathComponent("notes.txt"), encoding: .utf8) == "Secret plan")
        let permissions = try FileManager.default.attributesOfItem(atPath: events.url.appendingPathComponent("a.json").path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test func strippedRecordsStillDecode() throws {
        let events = try TemporaryFolder()
        let limits = try TemporaryFolder()
        try events.write("a.json", #"{"session_id":"a","state":"waiting","event":"Notification","at":1760352000,"message":"Allow?"}"#)

        PrivateMode.apply(true, events: events.url, limits: limits.url)
        var reader = RecordFolder<EventRecord>(url: events.url)

        #expect(reader.read().records.map(\.state) == [.waiting])
    }

    @Test func switchingOffRemovesTheMarker() throws {
        let events = try TemporaryFolder()
        let limits = try TemporaryFolder()
        PrivateMode.apply(true, events: events.url, limits: limits.url)

        PrivateMode.apply(false, events: events.url, limits: limits.url)

        #expect(!FileManager.default.fileExists(atPath: events.url.appendingPathComponent(PrivateMode.markerName).path))
    }

    @Test func privateModeShowsNoClaudeTextAndNoNames() {
        let events = [event("a", .waiting, cwd: "/x/web", title: "Secret plan", message: "Secret answer")]
        let named = [limits("a", sessionName: "Secret name")]

        let open = PrivateMode.shown(events: events, limits: named, enabled: false)
        let hidden = PrivateMode.shown(events: events, limits: named, enabled: true)

        #expect(open.names == ["a": "Secret name"])
        #expect(hidden.names.isEmpty)
        #expect(hidden.events.map(\.message) == [nil])
        #expect(SessionList.rows(from: hidden.events, now: noon, names: hidden.names).map(\.name) == ["web"])
        #expect(Texts(.english).sessionNotice(hidden.events[0]) == NoticeText(title: "web is waiting for you", body: "Needs your answer"))
    }

    @Test func aRecordWrittenLateIsSpottedForStripping() {
        #expect(PrivateMode.needsStripping(events: [event("a", .done, message: "late")], limits: []))
        #expect(PrivateMode.needsStripping(events: [], limits: [limits("a", sessionName: "late")]))
        #expect(!PrivateMode.needsStripping(events: [event("a", .done, title: nil)], limits: [limits("a")]))
    }

    @Test func cleanupLeavesTheMarkerAlone() throws {
        let events = try TemporaryFolder()
        let limits = try TemporaryFolder()
        PrivateMode.apply(true, events: events.url, limits: limits.url)

        let removed = FolderCleanup.removeExpired(in: events.url, now: Date().addingTimeInterval(30 * 24 * 3600))

        #expect(removed.isEmpty)
    }
}

struct StatusLineRequestTests {
    @Test func aRequestLeavesAMarkerThatCleanupKeeps() throws {
        let events = try TemporaryFolder()

        #expect(!StatusLineRequest.isPending(events: events.url))
        StatusLineRequest.send(events: events.url)
        StatusLineRequest.send(events: events.url)

        #expect(StatusLineRequest.isPending(events: events.url))
        #expect(FolderCleanup.removeExpired(in: events.url, now: Date().addingTimeInterval(30 * 24 * 3600)).isEmpty)
        var reader = RecordFolder<EventRecord>(url: events.url)
        #expect(reader.read().newlyFailed.isEmpty)
    }
}
