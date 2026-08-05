import Foundation
import OSLog
import Persistence
import UserNotifications

protocol NotificationScheduling: Sendable {
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async
    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
}

struct LiveNotificationCenter: NotificationScheduling {
    func add(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: options)
    }
}

enum RestTimerNotificationSound {
    /// IMA4-encoded CAF in the app bundle; required for reliable background notification playback.
    static let notificationFileName = "boxing-bell-notification"
    static let notificationFileExtension = "caf"

    static func resolved(soundEnabled: Bool) -> UNNotificationSound? {
        guard soundEnabled else { return nil }

        if Bundle.main.url(
            forResource: notificationFileName,
            withExtension: notificationFileExtension
        ) != nil {
            return UNNotificationSound(
                named: UNNotificationSoundName("\(notificationFileName).\(notificationFileExtension)")
            )
        }

        if Bundle.main.url(forResource: "boxing-bell", withExtension: "caf") != nil {
            return UNNotificationSound(named: UNNotificationSoundName("boxing-bell.caf"))
        }

        return .default
    }
}

@MainActor
final class RestTimerNotificationScheduler {
    private static let logger = Logger(subsystem: "com.cameronro.helm", category: "RestTimerNotification")

    private let center: any NotificationScheduling

    init(center: any NotificationScheduling = LiveNotificationCenter()) {
        self.center = center
    }

    func requestPermissionIfNeeded() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if !granted {
                Self.logger.warning("Rest-end notification permission not granted")
            }
        } catch {
            Self.logger.error(
                "Rest-end notification permission request failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func scheduleRestEndIfNeeded(
        sessionID: String,
        timerID: String,
        endsAt: Date,
        soundEnabled: Bool = true,
        now: Date = Date()
    ) async {
        guard RestTimerNotificationPlanner.shouldScheduleRestEndNotification(endsAt: endsAt, now: now),
              let interval = RestTimerNotificationPlanner.restEndFireInterval(endsAt: endsAt, now: now) else {
            await cancelRestNotification(sessionID: sessionID)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = "Time for your next set."
        content.sound = RestTimerNotificationSound.resolved(soundEnabled: soundEnabled)
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = RestTimerNotificationPlanner.notificationCategoryID
        content.userInfo = [
            RestTimerNotificationPlanner.sessionIDKey: sessionID,
            RestTimerNotificationPlanner.timerIDKey: timerID
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let identifier = RestTimerNotificationPlanner.notificationIdentifier(sessionID: sessionID)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        await cancelRestNotification(sessionID: sessionID)
        do {
            try await center.add(request)
            Self.logger.info(
                "Scheduled rest-end notification in \(interval, privacy: .public)s for session \(sessionID, privacy: .public)"
            )
        } catch {
            Self.logger.error(
                "Failed to schedule rest-end notification: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func cancelRestNotification(sessionID: String) async {
        let identifier = RestTimerNotificationPlanner.notificationIdentifier(sessionID: sessionID)
        await center.removePendingNotificationRequests(withIdentifiers: [identifier])
        await center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
