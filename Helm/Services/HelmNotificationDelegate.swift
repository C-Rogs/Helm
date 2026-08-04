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
        final class TaskIDBox: @unchecked Sendable {
            var id = UIBackgroundTaskIdentifier.invalid
        }
        let box = TaskIDBox()
        box.id = application.beginBackgroundTask(withName: "helm.endLiveActivities") {
            let taskID = box.id
            guard taskID != .invalid else { return }
            application.endBackgroundTask(taskID)
            box.id = .invalid
        }
        Task { @MainActor in
            defer {
                let taskID = box.id
                if taskID != .invalid {
                    application.endBackgroundTask(taskID)
                    box.id = .invalid
                }
            }
            await TrainBootstrap.sideEffects.endLiveActivitiesForTermination()
        }
    }
}

/// `UNUserNotificationCenter` invokes these on a background queue.
/// Never mutate SwiftUI / tabs / Observable here. Stash intent only; UI runs when
/// `scenePhase == .active` via `RestNotificationRouter.processPendingIfForeground()`.
final class HelmNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let content = notification.request.content
        let categoryIdentifier = content.categoryIdentifier
        let timerID = content.userInfo[RestTimerNotificationPlanner.timerIDKey] as? String
        let sessionID = content.userInfo[RestTimerNotificationPlanner.sessionIDKey] as? String
        nonisolated(unsafe) let finish = completionHandler

        Task { @MainActor in
            let options = await RestNotificationRouter.handleForegroundPresentation(
                categoryIdentifier: categoryIdentifier,
                timerID: timerID,
                sessionID: sessionID
            )
            finish(options)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let content = response.notification.request.content
        let categoryIdentifier = content.categoryIdentifier

        // `storePendingSessionID` is nonisolated (UserDefaults only). Safe on this queue.
        // Do not run UI/recovery here - schedule the same deferred MainActor path used on
        // scene activation (covers already-active taps and onChange-before-stash races).
        if RestNotificationLaunchPayload.isRestTimerNotification(categoryIdentifier: categoryIdentifier) {
            if let sessionID = RestNotificationLaunchPayload.sessionID(fromUserInfo: content.userInfo) {
                RestNotificationRouter.storePendingSessionID(sessionID)
            } else {
                RestNotificationRouter.storePendingSessionID(RestNotificationRouter.pendingTapWithoutSessionID)
            }
            Task { @MainActor in
                await RestNotificationRouter.processPendingIfForeground()
            }
        }

        completionHandler()
    }
}
