import Foundation

public enum BarTone: Equatable, Sendable {
    case normal
    /// Used ahead of the elapsed share of the window.
    case signal
    /// Nearly exhausted; takes priority over pace.
    case over
}

public struct Pace: Equatable, Sendable {
    /// 0–1, the share of the window's time already passed.
    public let elapsedFraction: Double
    /// Percentage points used beyond the elapsed share of the window; negative when behind it.
    public let delta: Double
    public let tone: BarTone

    static let signalDelta = 10.0
    static let overUsed = 90.0

    public init(reading: WindowReading, now: Date) {
        let start = reading.resetsAt.addingTimeInterval(-reading.kind.length)
        let elapsed = now.timeIntervalSince(start) / reading.kind.length
        elapsedFraction = min(max(elapsed, 0), 1)
        delta = reading.usedPercentage - elapsedFraction * 100
        if reading.usedPercentage >= Self.overUsed {
            tone = .over
        } else if delta >= Self.signalDelta {
            tone = .signal
        } else {
            tone = .normal
        }
    }
}

/// What the menu bar label shows. Unlike `WindowReading` it has no observation time, so the
/// same figures written again compare equal and the label is not redrawn.
public struct MenuBarFigure: Equatable, Sendable {
    public let kind: WindowKind
    public let percent: String
    public let resetsAt: Date
}

extension LimitsSummary {
    public var menuBarFigure: MenuBarFigure? {
        menuBarReading.map { MenuBarFigure(kind: $0.kind, percent: Texts.percent($0.usedPercentage), resetsAt: $0.resetsAt) }
    }

    /// The current window with the larger used share; the five-hour one on a tie.
    public var menuBarReading: WindowReading? {
        let readings = WindowKind.allCases.compactMap { kind -> WindowReading? in
            guard case .current(let reading) = status(of: kind) else { return nil }
            return reading
        }
        return readings.reduce(nil) { best, reading in
            guard let best else { return reading }
            return reading.usedPercentage > best.usedPercentage ? reading : best
        }
    }
}
