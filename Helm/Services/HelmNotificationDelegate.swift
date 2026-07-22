import DesignSystem
import Foundation
import Persistence
import UserNotifications

final class HelmNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await MainActor.run {
            deliverRestHapticIfNeeded(for: notification)
        }
        return [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            deliverRestHapticIfNeeded(for: response.notification)
        }
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
