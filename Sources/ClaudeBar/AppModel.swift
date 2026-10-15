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
    }

    private(set) var summary = LimitsSummary.empty
    private(set) var rows: [SessionRow] = []
    /// Observation skips an equal value, but `summary` changes with every limits write (its
    /// `lastObservedAt`). Kept apart, so the menu bar label redraws only when what it shows changes.
    private(set) var menuBarFigure: MenuBarFigure?
    private(set) var waitingCount = 0
    /// Moves only while the panel is open: nothing else shows relative times.
    private(set) var now = Date()
    private(set) var lastEventAt: Date?
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var loginError: String?
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
        tracker = ThresholdTracker(alerted: Self.alerted(from: defaults))
        limitsFolder = RecordFolder(url: directory.limits)
        eventsFolder = RecordFolder(url: directory.events)

        // Reading the permission is instant; asking for it waits on the user, so the data
        // loads first. A threshold crossed before the very first answer gets only a sound.
        Task {
            await notifier.refreshPermission()
            prepareFolders()
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

        summary = LimitsAggregator.summarize(limits.records, now: now)
        let names = SessionList.names(from: limits.records)
        rows = SessionList.rows(from: events.records, now: now, names: names)
        lastEventAt = events.records.map(\.at).max()
        menuBarFigure = summary.menuBarFigure
        waitingCount = rows.filter { $0.state == .waiting }.count

        let notices = detector.notices(in: events.records, now: now)
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
        let alerts = tracker.alerts(for: summary, threshold: threshold)
        guard !alerts.isEmpty else { return }
        defaults.set(Dictionary(uniqueKeysWithValues: tracker.alerted.map { ($0.key.rawValue, $0.value.timeIntervalSince1970) }), forKey: Keys.alerted)
        for alert in alerts {
            notifier.announce(
                id: "threshold:\(alert.reading.kind.rawValue):\(Int(alert.reading.resetsAt.timeIntervalSince1970))",
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
            loginError = nil
        } catch {
            loginError = texts.loginError(error)
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
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
        var delay = WakePlanner.nextWake(summary: summary, rows: rows, now: now).timeIntervalSince(now)
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

    private static func alerted(from defaults: UserDefaults) -> [WindowKind: Date] {
        let stored = defaults.dictionary(forKey: Keys.alerted) as? [String: Double] ?? [:]
        var alerted: [WindowKind: Date] = [:]
        for (key, seconds) in stored {
            if let kind = WindowKind(rawValue: key) {
                alerted[kind] = Date(timeIntervalSince1970: seconds)
            }
        }
        return alerted
    }
}
