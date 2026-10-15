import Foundation

/// Limits arrive only through Claude Code's status line, which the sandboxed app cannot add:
/// Claude Code's settings are out of its reach. Asking for one leaves this marker in `events/`;
/// the next hook event runs `configure.sh add-statusline` and removes it. Like the private mode
/// marker, its name ends neither in `.json` nor starts with a dot, so readers and cleanup pass it by.
public enum StatusLineRequest {
    public static let markerName = "statusline-request"

    public static func send(events: URL) {
        let marker = events.appendingPathComponent(markerName)
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        FileManager.default.createFile(atPath: marker.path, contents: nil, attributes: [.posixPermissions: 0o600])
    }

    public static func isPending(events: URL) -> Bool {
        FileManager.default.fileExists(atPath: events.appendingPathComponent(markerName).path)
    }
}
