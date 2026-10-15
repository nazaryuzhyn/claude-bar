// Draws ClaudeBar's app icon, the one banners show: the Claude mark on a macOS-shaped tile
// inside a gauge arc, a nod to the usage limits. Run from the project root: swift scripts/generate-icon.swift <variant> <output folder>
// <variant> is "terracotta" or "charcoal". Writes preview.png, AppIcon.iconset and AppIcon.icns.
import AppKit

struct Palette {
    let top: NSColor
    let bottom: NSColor
    let mark: NSColor
    let track: NSColor
    let gauge: NSColor
}

func color(_ rgb: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
}

let palettes: [String: Palette] = [
    "terracotta": Palette(top: color(0xE0866A), bottom: color(0xC25B3F), mark: color(0xFAF6EE), track: color(0xFAF6EE).withAlphaComponent(0.25), gauge: color(0x262624)),
    "charcoal": Palette(top: color(0x34322F), bottom: color(0x1C1B19), mark: color(0xD97757), track: color(0xFAF6EE).withAlphaComponent(0.12), gauge: color(0xF2A93B)),
]

let arguments = CommandLine.arguments
guard arguments.count == 3, let palette = palettes[arguments[1]] else {
    FileHandle.standardError.write(Data("usage: generate-icon.swift terracotta|charcoal <output folder>\n".utf8))
    exit(64)
}
let output = URL(fileURLWithPath: arguments[2], isDirectory: true)
// Run from the project root: the interpreter gives no reliable path of this file.
let markURL = URL(fileURLWithPath: "Resources/Icons/claude.pdf")
guard let mark = NSImage(contentsOf: markURL) else {
    FileHandle.standardError.write(Data("cannot read \(markURL.path)\n".utf8))
    exit(66)
}

/// The mark in one flat colour: draw it, then paint only where it is opaque.
func tinted(_ image: NSImage, _ tint: NSColor, size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        image.draw(in: rect)
        tint.setFill()
        rect.fill(using: .sourceAtop)
        return true
    }
}

/// Designed on Apple's 1024 grid: an 824-point tile with a soft drop shadow.
func render(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(pixels) / 1024
    NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)

    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 28
    shadow.set()
    palette.bottom.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: palette.top, ending: palette.bottom)?.draw(in: shape, angle: -90)

    let markSize: CGFloat = 380
    tinted(mark, palette.mark, size: markSize).draw(in: NSRect(x: 512 - markSize / 2, y: 512 - markSize / 2, width: markSize, height: markSize))

    // A 270-degree gauge open at the bottom, two thirds full, like the menu bar's limit.
    let center = NSPoint(x: 512, y: 512)
    for (color, end) in [(palette.track, CGFloat(-45)), (palette.gauge, CGFloat(225 - 270 * 0.66))] {
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: 300, startAngle: 225, endAngle: end, clockwise: true)
        arc.lineWidth = 44
        arc.lineCapStyle = .round
        color.setStroke()
        arc.stroke()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, to url: URL) {
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let iconset = output.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
write(render(pixels: 1024), to: output.appendingPathComponent("preview.png"))
for points in [16, 32, 128, 256, 512] {
    write(render(pixels: points), to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    write(render(pixels: points * 2), to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
print(iconset.path)
