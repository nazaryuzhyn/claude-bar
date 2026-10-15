import Foundation

public enum SoundKind: String, Sendable {
    case done
    case waiting
}

/// Keeps several sessions finishing together from playing a burst of completion sounds.
/// Waiting sounds are never held back: each one asks for the user.
public struct SoundGate: Sendable {
    static let doneCooldown: TimeInterval = 5
    private var lastDone: Date?

    public init() {}

    /// Call before sending the banner: the reservation is what later sounds are measured against.
    /// A clock that moved backwards resets the gate.
    public mutating func allows(_ kind: SoundKind, at now: Date) -> Bool {
        guard kind == .done else { return true }
        if let lastDone {
            let elapsed = now.timeIntervalSince(lastDone)
            if elapsed >= 0, elapsed < Self.doneCooldown { return false }
        }
        lastDone = now
        return true
    }
}
