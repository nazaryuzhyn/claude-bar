import Foundation

/// The folder the status line bridge, the hook and the app exchange files through.
public struct DataDirectory: Sendable, Equatable {
    public let root: URL

    public var limits: URL { root.appendingPathComponent("limits", isDirectory: true) }
    public var events: URL { root.appendingPathComponent("events", isDirectory: true) }

    public init(root: URL) {
        self.root = root
    }

    /// `CLAUDEBAR_DIR` points the app at the same scratch folder the shell scripts use in tests.
    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = realHome
    ) -> DataDirectory {
        if let override = environment["CLAUDEBAR_DIR"], !override.isEmpty {
            return DataDirectory(root: URL(fileURLWithPath: override, isDirectory: true))
        }
        return DataDirectory(root: home.appendingPathComponent("Library/Application Support/ClaudeBar", isDirectory: true))
    }

    /// The user's home even inside App Sandbox, where `homeDirectoryForCurrentUser` is the
    /// app's container: the hook and the bridge write under the real home.
    public static var realHome: URL {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}
