import Foundation

/// Private mode keeps what Claude wrote or titled out of banners, the panel and stored files.
/// The scripts run outside the sandbox and learn the setting from a marker file in `events/`;
/// its name ends neither in `.json` nor starts with a dot, so readers and cleanup pass it by.
public enum PrivateMode {
    public static let markerName = "private-mode"

    public static func apply(_ enabled: Bool, events: URL, limits: URL) {
        let manager = FileManager.default
        let marker = events.appendingPathComponent(markerName)
        guard enabled else {
            try? manager.removeItem(at: marker)
            return
        }
        if !manager.fileExists(atPath: marker.path) {
            manager.createFile(atPath: marker.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        strip(events: events, limits: limits)
    }

    /// What the app shows: in private mode, records without Claude's texts and no session names.
    public static func shown(events: [EventRecord], limits: [LimitsRecord], enabled: Bool) -> (events: [EventRecord], names: [String: String]) {
        enabled ? (events.map(\.redacted), [:]) : (events, SessionList.names(from: limits))
    }

    /// A record still holding Claude's text: the hook or the bridge wrote it while private mode
    /// was being switched on, after the files were stripped.
    public static func needsStripping(events: [EventRecord], limits: [LimitsRecord]) -> Bool {
        events.contains { $0.title != nil || $0.message != nil } || limits.contains { $0.sessionName != nil }
    }

    /// Records written before private mode was on still hold those texts; they go at once
    /// rather than when each session next writes or its file expires.
    public static func strip(events: URL, limits: URL) {
        strip(["title", "message"], from: events)
        strip(["session_name"], from: limits)
    }

    static func strip(_ keys: [String], from folder: URL) {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where name.hasSuffix(".json") && !name.hasPrefix(".") {
            let url = folder.appendingPathComponent(name)
            let modified = modificationDate(url)
            guard let data = try? Data(contentsOf: url),
                  var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  keys.contains(where: { object[$0] != nil }) else { continue }
            keys.forEach { object.removeValue(forKey: $0) }
            // A writer that renamed a newer record in meanwhile wins; this one would put the old state back.
            guard let stripped = try? JSONSerialization.data(withJSONObject: object),
                  modificationDate(url) == modified,
                  (try? stripped.write(to: url, options: .atomic)) != nil else { continue }
            try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    private static func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
