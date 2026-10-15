import AppKit
import SwiftUI

@main
enum Entry {
    static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.indices.contains(index + 1) {
            MainActor.assumeIsolated {
                Snapshot.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true))
            }
            return
        }
        ClaudeBarApp.main()
    }
}

struct ClaudeBarApp: App {
    // Not @State: with the macOS 27 SDK @State is a SwiftUI macro whose plugin Command Line
    // Tools do not ship. The App value is created once, so a plain reference is enough.
    private let model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Renders the panel and the menu bar label from the current data to PNG files, for reviewing
/// the design without screen recording access. AppKit-backed controls such as buttons do not render.
@MainActor
enum Snapshot {
    static func render(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let model = AppModel()
        model.reload()
        for (name, scheme, background) in [("light", ColorScheme.light, Color(white: 0.95)), ("dark", .dark, Color(white: 0.17))] {
            write(PanelView(model: model, fitsWindow: false).background(background).environment(\.colorScheme, scheme), to: folder.appendingPathComponent("panel-\(name).png"))
            write(MenuBarLabel(model: model).padding(6).background(background).environment(\.colorScheme, scheme), to: folder.appendingPathComponent("label-\(name).png"))
        }
    }

    private static func write(_ view: some View, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        try? png?.write(to: url)
    }
}
