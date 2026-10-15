import AppKit
import ClaudeBarCore
import Observation
import os
import UserNotifications

/// Banners and sounds. Adapted from Lunavect's AppFeatures (MIT, see THIRD_PARTY_NOTICES):
/// a session's newer banner replaces its older one, and when a banner cannot be shown the
/// sound plays directly.
@MainActor
@Observable
final class Notifier: NSObject {
    enum Permission {
        case unknown
        case allowed
        case denied
        /// Notification Center exists only for a bundled app; `swift run` gets sounds only.
        case unavailable
    }

    private(set) var permission: Permission = .unknown
    @ObservationIgnored private var gate = SoundGate()
    @ObservationIgnored private let center: UNUserNotificationCenter? =
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    /// NSSound stops when released, so each kind keeps its last sound alive.
    @ObservationIgnored private var playing: [SoundKind: NSSound] = [:]
    @ObservationIgnored private let logger = Logger(subsystem: "local.claudebar", category: "notify")

    override init() {
        super.init()
        center?.delegate = self
    }

    func refreshPermission() async {
        guard let center else {
            permission = .unavailable
            return
        }
        let status = await center.notificationSettings().authorizationStatus
        logger.debug("Notification authorization status: \(status.rawValue)")
        permission = switch status {
        case .authorized, .provisional: .allowed
        case .denied: .denied
        default: .unknown
        }
    }

    func requestPermission() async {
        guard let center else { return }
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            logger.debug("Notification authorization granted: \(granted)")
        } catch {
            logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
        }
        await refreshPermission()
    }

    /// Banners already delivered keep Claude's text in Notification Center; private mode takes them back.
    func removeSessionNotices() {
        guard let center else { return }
        Task {
            let ids = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix("session:") }
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    /// The permission is read again for every notice: it can change in System Settings while the
    /// app runs, and `add` reports success even when banners are not allowed.
    func announce(id: String, text: NoticeText, sound kind: SoundKind, soundsEnabled: Bool, bannersEnabled: Bool) {
        let playsSound = soundsEnabled && gate.allows(kind, at: Date())
        Task {
            await refreshPermission()
            deliver(id: id, text: text, sound: kind, playsSound: playsSound, bannersEnabled: bannersEnabled)
        }
    }

    private func deliver(id: String, text: NoticeText, sound kind: SoundKind, playsSound: Bool, bannersEnabled: Bool) {
        guard bannersEnabled, permission == .allowed, let center else {
            logger.debug("No banner (permission \(String(describing: self.permission), privacy: .public)); sound \(playsSound)")
            if playsSound { play(kind) }
            return
        }

        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        if playsSound {
            content.sound = UNNotificationSound(named: UNNotificationSoundName("\(kind.rawValue).wav"))
        }
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
            Task { @MainActor in
                if let error {
                    self.logger.error("Banner failed: \(error.localizedDescription, privacy: .public)")
                    if playsSound { self.play(kind) }
                } else {
                    self.logger.debug("Banner sent: \(id, privacy: .public)")
                }
            }
        }
    }

    func play(_ kind: SoundKind) {
        guard let url = Bundle.main.url(forResource: kind.rawValue, withExtension: "wav"),
              let sound = NSSound(contentsOf: url, byReference: true) else { return }
        playing[kind] = sound
        sound.play()
    }
}

extension Notifier: UNUserNotificationCenterDelegate {
    /// A menu bar app counts as frontmost while its panel is open; show banners anyway.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
