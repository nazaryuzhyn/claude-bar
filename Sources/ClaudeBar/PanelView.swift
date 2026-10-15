import AppKit
import os
import ClaudeBarCore
import SwiftUI

struct PanelView: View {
    let model: AppModel
    /// Off for `--snapshot`: ImageRenderer cannot draw the AppKit view the fitter uses.
    var fitsWindow = true

    var body: some View {
        Group {
            if model.showsSettings {
                SettingsPage(model: model) { model.showsSettings = false }
            } else {
                content
            }
        }
        .frame(width: 320)
        .background {
            if fitsWindow {
                GeometryReader { proxy in WindowFitter(height: proxy.size.height) }
                PanelVisibility { visible in
                    if visible { model.panelDidAppear() } else { model.panelDidDisappear() }
                }
            }
        }
    }

    private var content: some View {
        let sessions = model.panelSessions
        return VStack(alignment: .leading, spacing: 0) {
            if !sessions.waiting.isEmpty {
                section {
                    Text(model.texts.waitingHeader)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    ForEach(sessions.waiting) { row in
                        SessionRowView(row: row, texts: model.texts, now: model.now, calendar: model.calendar, showsMessage: true)
                    }
                }
            }

            section {
                limits
            }
            Divider()

            section {
                if sessions.recent.isEmpty {
                    if sessions.waiting.isEmpty {
                        Text(model.hooksLookBlocked ? model.texts.noSessionEvents : model.texts.noSessions)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(sessions.recent) { row in
                        SessionRowView(row: row, texts: model.texts, now: model.now, calendar: model.calendar, showsMessage: false)
                    }
                    if sessions.moreCount > 0 {
                        Text(model.texts.moreSessions(sessions.moreCount))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            section {
                HStack(alignment: .firstTextBaseline) {
                    Button(model.texts.settings) { model.showsSettings = true }
                    Spacer()
                    // How fresh the limits are; with no status line there are none to date.
                    if model.lastObservedAt != nil {
                        Text(model.texts.updated(model.lastObservedAt, now: model.now))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                        Spacer()
                    }
                    Button(model.texts.quit) { NSApplication.shared.terminate(nil) }
                }
                .buttonStyle(ActionButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var limits: some View {
        if model.summaries.isEmpty {
            Text(model.statusLineLooksMissing ? model.texts.noStatusLine : model.texts.noLimits)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        ForEach(model.summaries) { summary in
            if let profile = summary.profile {
                Text(model.texts.profile(profile))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, summary.id == model.summaries.first?.id ? 0 : 8)
            }
            if summary.planReportsNoLimits {
                // Usage-billed plans have no windows to show, but the day's spend is what they pay.
                Text(model.texts.costToday(summary.costToday))
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                Text(model.texts.planReportsNoLimits)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if summary.fiveHour == nil, summary.sevenDay == nil {
                Text(model.texts.noLimits)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(WindowKind.allCases, id: \.self) { kind in
                    if let status = summary.status(of: kind) {
                        LimitRow(kind: kind, status: status, texts: model.texts, now: model.now, calendar: model.calendar)
                    }
                }
            }
        }
    }

    private func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct LimitRow: View {
    let kind: WindowKind
    let status: WindowStatus
    let texts: Texts
    let now: Date
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(texts.windowTitle(kind))
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                if reading != nil {
                    Text(texts.usedCaption)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Text(percentText)
                    .font(.system(size: 22, weight: .semibold).width(.expanded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.text(for: pace?.tone ?? .normal))
            }
            LimitBar(used: reading?.usedPercentage ?? 0, elapsed: pace?.elapsedFraction, tone: pace?.tone ?? .normal)
                .help(texts.paceHelp)
            if let pace {
                Text(texts.paceStatus(pace))
                    .font(.system(size: 11))
                    .foregroundStyle(pace.tone == .normal ? Color.secondary : Palette.text(for: pace.tone))
            }
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private var reading: WindowReading? {
        guard case .current(let reading) = status else { return nil }
        return reading
    }

    private var pace: Pace? {
        reading.map { Pace(reading: $0, now: now) }
    }

    private var percentText: String {
        reading.map { Texts.percent($0.usedPercentage) } ?? "—"
    }

    private var detail: String {
        guard let reading else { return texts.resetPassed }
        return texts.resetText(reading.resetsAt, now: now, calendar: calendar)
    }
}

/// Fill is the used share; the tick marks how much of the window's time has passed.
struct LimitBar: View {
    let used: Double
    let elapsed: Double?
    let tone: BarTone

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.track)
                    .frame(height: 6)
                Capsule()
                    .fill(Palette.fill(for: tone))
                    .frame(width: width * min(max(used / 100, 0), 1), height: 6)
                if let elapsed {
                    Capsule()
                        .fill(Palette.paceTick)
                        .frame(width: 2, height: 14)
                        .offset(x: min(max(width * elapsed - 1, 0), width - 2))
                }
            }
            .frame(height: 14)
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

struct SessionRowView: View {
    let row: SessionRow
    let texts: Texts
    let now: Date
    let calendar: Calendar
    let showsMessage: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            glyph
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                if showsMessage, let message = row.message {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if !showsMessage {
                Text(texts.status(of: row))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text(texts.time(of: row, now: now, calendar: calendar))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .opacity(row.freshness == .unknown ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var glyph: some View {
        switch (row.state, row.freshness) {
        case (_, .unknown):
            Image(systemName: "questionmark.circle").foregroundStyle(.tertiary)
        case (.working, _):
            Image(systemName: "circle").foregroundStyle(.secondary)
        case (.waiting, _):
            Image(systemName: "circle.fill").foregroundStyle(Palette.signal)
        case (.done, _):
            Image(systemName: "checkmark").foregroundStyle(Palette.done)
        }
    }
}

/// MenuBarExtra grows its window with the content but never shrinks it back: a 375-point
/// window kept 140 points of content after the sessions ended. This fits the window to the
/// content's measured height, keeping the top edge under the menu bar. The window's own
/// `contentView.fittingSize` reports a height of 0 here, so SwiftUI measures instead.
struct WindowFitter: NSViewRepresentable {
    let height: CGFloat

    private static let logger = Logger(subsystem: "local.claudebar", category: "window")

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        let height = height
        DispatchQueue.main.async {
            guard let window = view.window, height > 0 else { return }
            let target = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: window.frame.width, height: height)).height
            Self.logger.debug("Fit: window \(window.frame.height) content \(height) visible \(window.isVisible)")
            guard abs(window.frame.height - target) > 0.5 else { return }
            var frame = window.frame
            frame.origin.y += frame.height - target
            frame.size.height = target
            window.setFrame(frame, display: true)
        }
    }
}

/// Reports the panel window being shown or hidden. MenuBarExtra does not call `onDisappear`
/// when the panel closes (seen in the log), so the window's own occlusion state tells.
struct PanelVisibility: NSViewRepresentable {
    let onChange: @MainActor (Bool) -> Void

    private static let logger = Logger(subsystem: "local.claudebar", category: "window")

    func makeNSView(context: Context) -> ObserverView {
        ObserverView(onChange: onChange)
    }

    func updateNSView(_ view: ObserverView, context: Context) {}

    final class ObserverView: NSView {
        private let onChange: @MainActor (Bool) -> Void
        private var observer: NSObjectProtocol?

        init(onChange: @escaping @MainActor (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    guard let self, let window else { return }
                    let visible = window.occlusionState.contains(.visible)
                    PanelVisibility.logger.debug("Panel visible: \(visible)")
                    self.onChange(visible)
                }
            }
        }
    }
}

/// Panel actions in the primary text colour: the borderless style draws them grey in a
/// menu bar window, where they read as disabled.
struct ActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(.primary)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}
