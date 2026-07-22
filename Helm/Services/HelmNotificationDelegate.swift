import DesignSystem
import Foundation
import Persistence
import UserNotifications

@MainActor
final class HelmNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = HelmNotificationDelegate()

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        deliverRestHapticIfNeeded(for: notification)
        return [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        deliverRestHapticIfNeeded(for: response.notification)
    }

    private func deliverRestHapticIfNeeded(for notification: UNNotification) {
        let content = notification.request.content
        let timerID = content.userInfo[RestTimerNotificationPlanner.timerIDKey] as? String
        WorkoutHapticCoordinator.handleRestNotification(
            categoryIdentifier: content.categoryIdentifier,
            timerID: timerID
        )
    }
}
