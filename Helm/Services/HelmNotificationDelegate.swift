import DesignSystem
import Diagnostics
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
        if let response = launchOptions?[.remoteNotification] as? [AnyHashable: Any],
           let sessionID = response[RestTimerNotificationPlanner.sessionIDKey] as? String {
            RestNotificationRouter.storePendingSessionID(sessionID)
        }
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        TrainBootstrap.sideEffects.endLiveActivitiesForTermination()
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
        let isForeground = await MainActor.run { AppLifecycleState.isForeground }
        await MainActor.run {
            WorkoutHapticCoordinator.handleRestNotification(
                categoryIdentifier: categoryIdentifier,
                timerID: timerID
            )
        }
        if RestTimerNotificationPlanner.shouldSuppressForegroundPresentation(
            categoryIdentifier: categoryIdentifier,
            isAppForeground: isForeground
        ) {
            return []
        }
        return [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        let categoryIdentifier = content.categoryIdentifier
        let timerID = content.userInfo[RestTimerNotificationPlanner.timerIDKey] as? String
        let sessionID = content.userInfo[RestTimerNotificationPlanner.sessionIDKey] as? String
        await MainActor.run {
            WorkoutHapticCoordinator.handleRestNotification(
                categoryIdentifier: categoryIdentifier,
                timerID: timerID
            )
            Task {
                await RestNotificationRouter.handleRestNotificationTap(sessionID: sessionID)
            }
        }
    }
}
