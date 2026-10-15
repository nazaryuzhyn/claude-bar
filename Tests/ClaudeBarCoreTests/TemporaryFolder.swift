import Foundation

/// A folder under the system temporary directory, removed when the test releases it.
final class TemporaryFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func write(_ name: String, _ text: String) throws {
        try Data(text.utf8).write(to: url.appendingPathComponent(name))
    }

    func remove(_ name: String) throws {
        try FileManager.default.removeItem(at: url.appendingPathComponent(name))
    }
}
