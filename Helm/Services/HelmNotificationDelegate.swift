import DesignSystem
import Foundation
import Persistence
import UserNotifications

final class HelmNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    nonisolated(unsafe) static let shared = HelmNotificationDelegate()

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await deliverRestHapticIfNeeded(for: notification)
        return [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await deliverRestHapticIfNeeded(for: response.notification)
    }

    @MainActor
    private func deliverRestHapticIfNeeded(for notification: UNNotification) {
        let content = notification.request.content
        let timerID = content.userInfo[RestTimerNotificationPlanner.timerIDKey] as? String
        WorkoutHapticCoordinator.handleRestNotification(
            categoryIdentifier: content.categoryIdentifier,
            timerID: timerID
        )
    }
}
