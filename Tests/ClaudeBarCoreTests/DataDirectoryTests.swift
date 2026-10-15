import Foundation
import Testing
@testable import ClaudeBarCore

struct DataDirectoryTests {
    private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)

    @Test func defaultsToApplicationSupport() {
        let directory = DataDirectory.resolve(environment: [:], home: home)

        #expect(directory.root.path == "/Users/someone/Library/Application Support/ClaudeBar")
        #expect(directory.limits.path == "/Users/someone/Library/Application Support/ClaudeBar/limits")
        #expect(directory.events.path == "/Users/someone/Library/Application Support/ClaudeBar/events")
    }

    @Test func environmentOverridesDefault() {
        let directory = DataDirectory.resolve(environment: ["CLAUDEBAR_DIR": "/private/tmp/claudebar-test"], home: home)

        #expect(directory.root.path == "/private/tmp/claudebar-test")
        #expect(directory.events.path == "/private/tmp/claudebar-test/events")
    }

    @Test func emptyOverrideFallsBackToDefault() {
        let directory = DataDirectory.resolve(environment: ["CLAUDEBAR_DIR": ""], home: home)

        #expect(directory.root.path == "/Users/someone/Library/Application Support/ClaudeBar")
    }
}
