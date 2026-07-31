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
        if let sessionID = RestNotificationLaunchOptions.pendingSessionID(from: launchOptions) {
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
        guard RestNotificationLaunchPayload.isRestTimerNotification(categoryIdentifier: content.categoryIdentifier) else {
            return
        }

        let categoryIdentifier = content.categoryIdentifier
        let userInfo = content.userInfo
        let timerID = userInfo[RestTimerNotificationPlanner.timerIDKey] as? String
        let sessionID = RestNotificationLaunchPayload.sessionID(fromUserInfo: userInfo)

        let shouldHandleImmediately = await MainActor.run { () -> Bool in
            if let sessionID {
                RestNotificationRouter.storePendingSessionID(sessionID)
            }
            WorkoutHapticCoordinator.handleRestNotification(
                categoryIdentifier: categoryIdentifier,
                timerID: timerID
            )
            return TrainBootstrap.hasCompletedLaunchRecovery
        }

        if shouldHandleImmediately {
            await RestNotificationRouter.handleRestNotificationTap(sessionID: sessionID)
        }
    }
}
