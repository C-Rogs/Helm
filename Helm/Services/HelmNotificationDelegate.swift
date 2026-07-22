import DesignSystem
import Foundation
import Persistence
import UIKit
import UserNotifications

final class HelmAppDelegate: NSObject, UIApplicationDelegate {
    private let notificationDelegate = HelmNotificationDelegate()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        notificationDelegate.configure()
        return true
    }
}

final class HelmNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let categoryIdentifier = notification.request.content.categoryIdentifier
        let timerID = notification.request.content.userInfo[RestTimerNotificationPlanner.timerIDKey] as? String
        await MainActor.run {
            WorkoutHapticCoordinator.handleRestNotification(
                categoryIdentifier: categoryIdentifier,
                timerID: timerID
            )
        }
        return [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let categoryIdentifier = response.notification.request.content.categoryIdentifier
        let timerID = response.notification.request.content.userInfo[RestTimerNotificationPlanner.timerIDKey] as? String
        await MainActor.run {
            WorkoutHapticCoordinator.handleRestNotification(
                categoryIdentifier: categoryIdentifier,
                timerID: timerID
            )
        }
    }
}
