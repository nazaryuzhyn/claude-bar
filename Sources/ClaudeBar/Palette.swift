import AppKit
import ClaudeBarCore
import SwiftUI

/// Colour marks a state that needs attention, never the brand; neutral tones come from the system.
enum Palette {
    static let signal = dynamic(light: 0xB86E00, dark: 0xF2A93B)
    static let done = dynamic(light: 0x1F8A5B, dark: 0x4CC38A)
    static let over = dynamic(light: 0xC9303E, dark: 0xF0616D)
    static let track = Color.primary.opacity(0.12)
    static let paceTick = Color.primary

    static func fill(for tone: BarTone) -> Color {
        switch tone {
        case .normal: Color.primary.opacity(0.5)
        case .signal: signal
        case .over: over
        }
    }

    static func text(for tone: BarTone) -> Color {
        switch tone {
        case .normal: Color.primary
        case .signal: signal
        case .over: over
        }
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(rgb: dark) : NSColor(rgb: light)
        })
    }
}

extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
