import Foundation
import Persistence
import UserNotifications

protocol NotificationScheduling: Sendable {
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
}

struct LiveNotificationCenter: NotificationScheduling {
    func add(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: options)
    }
}

@MainActor
final class RestTimerNotificationScheduler {
    private let center: any NotificationScheduling

    init(center: any NotificationScheduling = LiveNotificationCenter()) {
        self.center = center
    }

    func requestPermissionIfNeeded() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func scheduleRestEndIfNeeded(sessionID: String, endsAt: Date, now: Date = Date()) async {
        guard RestTimerNotificationPlanner.shouldScheduleRestEndNotification(endsAt: endsAt, now: now),
              let interval = RestTimerNotificationPlanner.restEndFireInterval(endsAt: endsAt, now: now) else {
            await cancelRestNotification(sessionID: sessionID)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = "Time for your next set."
        content.sound = .default
        content.categoryIdentifier = RestTimerNotificationPlanner.notificationCategoryID

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let identifier = RestTimerNotificationPlanner.notificationIdentifier(sessionID: sessionID)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        await cancelRestNotification(sessionID: sessionID)
        try? await center.add(request)
    }

    func cancelRestNotification(sessionID: String) async {
        let identifier = RestTimerNotificationPlanner.notificationIdentifier(sessionID: sessionID)
        await center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
