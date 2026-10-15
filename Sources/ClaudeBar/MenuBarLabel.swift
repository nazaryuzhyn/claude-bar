import AppKit
import ClaudeBarCore
import SwiftUI

struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        let figure = model.menuBarFigure
        let waiting = model.waitingCount
        HStack(spacing: 4) {
            Self.claudeMark
            if let figure {
                Text(figure.percent)
                    .monospacedDigit()
            }
            if waiting > 0 {
                Image(nsImage: Self.badge(count: waiting))
            }
        }
        // Date(), not model.now: that stands still while the panel is closed.
        .accessibilityLabel(model.texts.menuBarDescription(figure, waiting: waiting, now: Date(), calendar: model.calendar))
    }

    /// The Claude mark as a template image, so it follows the menu bar's light or dark look.
    /// Outside the app bundle (`swift run`, `--snapshot` from a debug build) an SF Symbol stands in.
    static let claudeMark: Image = {
        guard let url = Bundle.main.url(forResource: "claude", withExtension: "pdf"),
              let image = NSImage(contentsOf: url) else {
            return Image(systemName: "asterisk")
        }
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        return Image(nsImage: image)
    }()

    /// The menu bar renders label images as templates; this one is drawn in colour on purpose,
    /// the only colour there, so a waiting session stands out.
    static func badge(count: Int) -> NSImage {
        let text = NSAttributedString(string: "\(count)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.black.withAlphaComponent(0.85),
        ])
        let textSize = text.size()
        let size = NSSize(width: max(16, textSize.width + 10), height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor(rgb: 0xF2A93B).setFill()
            NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            text.draw(at: NSPoint(x: (rect.width - textSize.width) / 2, y: (rect.height - textSize.height) / 2))
            return true
        }
        image.isTemplate = false
        return image
    }
}
