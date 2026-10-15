import AppKit
import ClaudeBarCore
import Foundation
import Observation
import os
import ServiceManagement

@MainActor
@Observable
final class AppModel {
    private enum Keys {
        static let sounds = "soundsEnabled"
        static let banners = "bannersEnabled"
        static let threshold = "thresholdPercent"
        static let alerted = "thresholdAlerted"
        static let language = "language"
        static let privateMode = "privateMode"
        static let sawHookEvent = "sawHookEvent"
    }

    /// One per Claude Code profile, the default one first.
    private(set) var summaries: [LimitsSummary] = []
    private(set) var rows: [SessionRow] = []
    /// Observation skips an equal value, but `summaries` change with every limits write (their
    /// `lastObservedAt`). Kept apart, so the menu bar label redraws only when what it shows changes.
    private(set) var menuBarFigure: MenuBarFigure?
    private(set) var waitingCount = 0
    /// Moves only while the panel is open: nothing else shows relative times.
    private(set) var now = Date()
    private(set) var lastEventAt: Date?
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// The system's description; the view adds the lead-in in the current language.
    private(set) var loginErrorDetail: String?
    /// The panel's hint that a company policy may block the hooks.
    private(set) var hooksLookBlocked = false
    /// The panel's note that limits need a status line, which this setup has none of.
    private(set) var statusLineLooksMissing = false
    /// Settings asked for a status line and the next hook event has not added it yet.
    private(set) var statusLineRequested = false
    /// Lives here rather than in the view: Command Line Tools cannot expand `@State` (see ClaudeBarApp).
    var showsSettings = false

    var soundsEnabled: Bool {
        didSet { defaults.set(soundsEnabled, forKey: Keys.sounds) }
    }

    var bannersEnabled: Bool {
        didSet {
            defaults.set(bannersEnabled, forKey: Keys.banners)
            if bannersEnabled { Task { await notifier.requestPermission() } }
        }
    }

    var threshold: Double {
        didSet { defaults.set(threshold, forKey: Keys.threshold) }
    }

    var language: Language {
        didSet {
            defaults.set(language.rawValue, forKey: Keys.language)
            texts = Texts(language)
        }
    }
    private(set) var texts: Texts

    var privateMode: Bool {
        didSet {
            defaults.set(privateMode, forKey: Keys.privateMode)
            PrivateMode.apply(privateMode, events: directory.events, limits: directory.limits)
            if privateMode { notifier.removeSessionNotices() }
            reload()
        }
    }

    var lastObservedAt: Date? { summaries.compactMap(\.lastObservedAt).max() }

    let notifier = Notifier()
    /// Follows a time zone change while the app runs for days.
    let calendar = Calendar.autoupdatingCurrent

    @ObservationIgnored private let directory = DataDirectory.resolve()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var limitsFolder: RecordFolder<LimitsRecord>
    @ObservationIgnored private var eventsFolder: RecordFolder<EventRecord>
    @ObservationIgnored private var detector = TransitionDetector()
    @ObservationIgnored private var tracker: ThresholdTracker
    @ObservationIgnored private var watchers: [FolderWatcher] = []
    /// One-shot, set for the next moment something changes without a file write (see WakePlanner).
    @ObservationIgnored private var wakeTimer: Timer?
    /// Runs only while the panel is open, to age relative times the user is looking at.
    @ObservationIgnored private var panelTimer: Timer?
    @ObservationIgnored private var reloadScheduled = false
    @ObservationIgnored private var panelVisible = false
    @ObservationIgnored private var systemObservers: [NSObjectProtocol] = []
    @ObservationIgnored private let logger = Logger(subsystem: "local.claudebar", category: "data")

    var panelSessions: PanelSessions { SessionList.panel(from: rows) }

    init() {
        defaults.register(defaults: [Keys.sounds: true, Keys.banners: true, Keys.threshold: 80.0])
        soundsEnabled = defaults.bool(forKey: Keys.sounds)
        bannersEnabled = defaults.bool(forKey: Keys.banners)
        threshold = defaults.double(forKey: Keys.threshold)
        let language = defaults.string(forKey: Keys.language).flatMap(Language.init(rawValue:)) ?? Language.preferred()
        self.language = language
        texts = Texts(language)
        privateMode = defaults.bool(forKey: Keys.privateMode)
        tracker = ThresholdTracker(alerted: Self.alerted(from: defaults))
        limitsFolder = RecordFolder(url: directory.limits)
        eventsFolder = RecordFolder(url: directory.events)

        // Reading the permission is instant; asking for it waits on the user, so the data
        // loads first. A threshold crossed before the very first answer gets only a sound.
        Task {
            await notifier.refreshPermission()
            prepareFolders()
            PrivateMode.apply(privateMode, events: directory.events, limits: directory.limits)
            watchFolders()
            observeSystemChanges()
            reload()
            if bannersEnabled, notifier.permission == .unknown {
                await notifier.requestPermission()
            }
        }
    }

    func reload() {
        let now = Date()
        if panelVisible { self.now = now }
        let limits = limitsFolder.read()
        let events = eventsFolder.read()
        for name in limits.newlyFailed + events.newlyFailed {
            logger.error("Skipped an unreadable record: \(name, privacy: .public)")
        }

        summaries = LimitsAggregator.summarizeProfiles(limits.records, now: now)
        // A record can still hold Claude's text when a script wrote it while private mode was
        // being switched on; it is hidden here and stripped from disk.
        if privateMode, PrivateMode.needsStripping(events: events.records, limits: limits.records) {
            PrivateMode.strip(events: directory.events, limits: directory.limits)
        }
        let (eventRecords, names) = PrivateMode.shown(events: events.records, limits: limits.records, enabled: privateMode)
        rows = SessionList.rows(from: eventRecords, now: now, names: names)
        lastEventAt = eventRecords.map(\.at).max()
        if !eventRecords.isEmpty, !defaults.bool(forKey: Keys.sawHookEvent) {
            defaults.set(true, forKey: Keys.sawHookEvent)
        }
        hooksLookBlocked = SessionList.hooksLookBlocked(everSawHookEvent: defaults.bool(forKey: Keys.sawHookEvent), statusLineSeen: lastObservedAt != nil)
        statusLineLooksMissing = SessionList.statusLineLooksMissing(events: eventRecords, summaries: summaries)
        statusLineRequested = statusLineLooksMissing && StatusLineRequest.isPending(events: directory.events)
        menuBarFigure = LimitsAggregator.menuBarFigure(of: summaries)
        waitingCount = rows.filter { $0.state == .waiting }.count

        let notices = detector.notices(in: eventRecords, now: now)
        logger.debug("Read \(limits.records.count) limits and \(events.records.count) sessions; \(notices.count) to announce")
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        for record in notices {
            let showsBanner = NoticePolicy.showsBanner(host: record.host, frontmost: frontmost)
            if !showsBanner {
                logger.debug("No banner: \(record.host ?? "", privacy: .public) is in front")
            }
            notifier.announce(
                id: "session:\(record.sessionID)",
                text: texts.sessionNotice(record, name: names[record.sessionID]),
                sound: record.state == .done ? .done : .waiting,
                soundsEnabled: soundsEnabled,
                bannersEnabled: bannersEnabled && showsBanner
            )
        }

        announceThresholds(now: now)
        scheduleWake(now: now)
    }

    func panelDidAppear() {
        panelVisible = true
        reload()
        panelTimer?.invalidate()
        panelTimer = Self.timer(after: 30, repeats: true, tolerance: 5) { [weak self] in
            self?.logger.debug("Panel timer tick")
            self?.reload()
        }
    }

    func panelDidDisappear() {
        panelVisible = false
        panelTimer?.invalidate()
        panelTimer = nil
    }

    private func announceThresholds(now: Date) {
        let alerts = summaries.flatMap { tracker.alerts(for: $0, threshold: threshold) }
        guard !alerts.isEmpty else { return }
        defaults.set(tracker.alerted.mapValues(\.timeIntervalSince1970), forKey: Keys.alerted)
        for alert in alerts {
            notifier.announce(
                id: "threshold:\(ThresholdTracker.key(alert.reading.kind, configDir: alert.configDir)):\(Int(alert.reading.resetsAt.timeIntervalSince1970))",
                text: texts.thresholdNotice(alert, now: now, calendar: calendar),
                sound: .waiting,
                soundsEnabled: soundsEnabled,
                bannersEnabled: bannersEnabled
            )
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginErrorDetail = nil
        } catch {
            loginErrorDetail = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func requestStatusLine() {
        StatusLineRequest.send(events: directory.events)
        statusLineRequested = true
    }

    func sendTest() {
        notifier.announce(
            id: "test",
            text: texts.sampleNotice,
            sound: .done,
            soundsEnabled: soundsEnabled,
            bannersEnabled: bannersEnabled
        )
    }

    private func scheduleWake(now: Date) {
        wakeTimer?.invalidate()
        let wakes = (summaries.isEmpty ? [.empty] : summaries).map { WakePlanner.nextWake(summary: $0, rows: rows, now: now) }
        var delay = (wakes.min() ?? now).timeIntervalSince(now)
        // A folder that could not be watched yet (not created before launch) is retried soon.
        if watchers.count < 2 { delay = min(delay, 60) }
        // A tolerance lets macOS coalesce this wake with others; a minute late is invisible here.
        wakeTimer = Self.timer(after: delay, repeats: false, tolerance: min(60, delay / 10)) { [weak self] in self?.wake() }
    }

    /// Also restores a deleted folder and its watcher.
    private func wake() {
        FolderCleanup.removeExpired(in: directory.limits, now: Date())
        FolderCleanup.removeExpired(in: directory.events, now: Date())
        prepareFolders()
        // A recreated events/ folder has lost the marker.
        PrivateMode.apply(privateMode, events: directory.events, limits: directory.limits)
        watchFolders()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        reload()
    }

    private func prepareFolders() {
        // The sandbox allows only these two; install.sh and the scripts create their parent.
        for folder in [directory.limits, directory.events] {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }

    private func watchFolders() {
        watchers = [directory.limits, directory.events].compactMap { url in
            FolderWatcher(url: url) { [weak self] folderGone in
                Task { @MainActor in
                    // A folder that is not back yet fails to open; scheduleWake then retries within a minute.
                    if folderGone { self?.watchFolders() }
                    self?.scheduleReload()
                }
            }
        }
    }

    /// After sleep or a clock change the planned wake can be late or wrong. Each of these is a
    /// single notification, so listening costs nothing while idle.
    private func observeSystemChanges() {
        let wake: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.wake() }
        }
        systemObservers = [
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: wake),
            NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main, using: wake),
            NotificationCenter.default.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main, using: wake),
        ]
    }

    /// A burst of hook events becomes one read.
    private func scheduleReload() {
        guard !reloadScheduled else { return }
        reloadScheduled = true
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            reloadScheduled = false
            reload()
        }
    }

    private static func timer(after interval: TimeInterval, repeats: Bool, tolerance: TimeInterval, action: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats) { _ in
            MainActor.assumeIsolated { action() }
        }
        timer.tolerance = tolerance
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private static func alerted(from defaults: UserDefaults) -> [String: Date] {
        let stored = defaults.dictionary(forKey: Keys.alerted) as? [String: Double] ?? [:]
        return stored.mapValues(Date.init(timeIntervalSince1970:))
    }
}
