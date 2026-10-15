import Foundation

/// Reads every `*.json` record in one folder.
///
/// The writers replace files atomically, so a file that fails to parse is damage rather than
/// a write in progress: its session keeps the last record that parsed.
public struct RecordFolder<Record: Decodable & Sendable>: Sendable {
    public struct Snapshot: Sendable {
        public let records: [Record]
        /// Files that fail now but did not fail on the previous read, so each failure is reported once.
        public let newlyFailed: [String]
    }

    public let url: URL
    private var lastGood: [String: Record] = [:]
    private var failing: Set<String> = []

    public init(url: URL) {
        self.url = url
    }

    public mutating func read() -> Snapshot {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        let files = names.filter { $0.hasSuffix(".json") }.sorted()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(Self.plausibleDate)

        var good: [String: Record] = [:]
        var failed: Set<String> = []
        for name in files {
            if let data = try? Data(contentsOf: url.appendingPathComponent(name)),
               let record = try? decoder.decode(Record.self, from: data) {
                good[name] = record
            } else {
                failed.insert(name)
                good[name] = lastGood[name]
            }
        }

        let newlyFailed = failed.subtracting(failing).sorted()
        lastGood = good
        failing = failed
        return Snapshot(records: files.compactMap { good[$0] }, newlyFailed: newlyFailed)
    }

    /// Seconds since 1970 within 2000–2100. Anything else is damage, and turning it into minutes
    /// for display would overflow `Int` and crash the app on every read.
    static func plausibleDate(_ decoder: Decoder) throws -> Date {
        let seconds = try decoder.singleValueContainer().decode(Double.self)
        guard (946_684_800.0...4_102_444_800.0).contains(seconds) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Implausible time \(seconds)"))
        }
        return Date(timeIntervalSince1970: seconds)
    }
}
