import DesignSystem
import Diagnostics
import Foundation
import Persistence
import UserNotifications

private let restNotificationPendingSessionIDKey = "helm.pendingRestNotificationSessionID"

@MainActor
enum RestNotificationRouter {
    /// Stored when the notification tap has no session id in userInfo.
    nonisolated static let pendingTapWithoutSessionID = "__helm_pending_rest_tap__"

    private static var isHandlingNotification = false

    nonisolated static func storePendingSessionID(_ sessionID: String) {
        UserDefaults.standard.set(sessionID, forKey: restNotificationPendingSessionIDKey)
        Task { @MainActor in
            await DiagnosticsLog.shared.record(
                category: .logger,
                level: .info,
                message: "Stored pending rest notification session",
                context: ["sessionID": sessionID]
            )
        }
    }

    nonisolated static func consumePendingSessionID() -> String? {
        guard let sessionID = UserDefaults.standard.string(forKey: restNotificationPendingSessionIDKey) else {
            return nil
        }
        UserDefaults.standard.removeObject(forKey: restNotificationPendingSessionIDKey)
        return sessionID
    }

    static func handleRestNotificationTap(sessionID: String?) async {
        guard !isHandlingNotification else { return }
        isHandlingNotification = true
        defer { isHandlingNotification = false }

        let resolvedSessionID: String? = {
            guard let sessionID else { return nil }
            return sessionID == pendingTapWithoutSessionID ? nil : sessionID
        }()

        await reclaimMainThread()

        await DiagnosticsLog.shared.record(
            category: .logger,
            level: .info,
            message: "Rest notification tap recovery began",
            context: ["expectedSessionID": resolvedSessionID ?? "none"]
        )

        AppTabRouter.shared.openTrain()

        if TrainBootstrap.sessionController.snapshot == nil {
            await TrainBootstrap.sessionController.recoverPersistedSession()
        }

        await reclaimMainThread()

        WorkoutHapticCoordinator.handleRestNotification(
            categoryIdentifier: RestTimerNotificationPlanner.notificationCategoryID,
            timerID: nil
        )

        let activeID = TrainBootstrap.sessionController.snapshot?.session.id
        let outcome = RestNotificationRecoveryPolicy.evaluate(
            expectedSessionID: resolvedSessionID,
            activeSessionID: activeID
        )

        switch outcome {
        case .noActiveSession(let expected):
            await DiagnosticsLog.shared.record(
                category: .logger,
                level: .info,
                message: "Rest notification recovery: no active session",
                context: ["expectedSessionID": expected ?? "none"]
            )
            await TrainBootstrap.sideEffects.reconcileLiveActivitiesOnLaunch(hasActiveSession: false)
            return

        case .sessionMismatch(let expected, let active):
            await DiagnosticsLog.shared.record(
                category: .logger,
                level: .info,
                message: "Rest notification session mismatch",
                context: ["expected": expected, "active": active]
            )

        case .recovered(let recoveredSessionID):
            await DiagnosticsLog.shared.record(
                category: .logger,
                level: .info,
                message: "Rest notification recovery: session restored",
                context: ["sessionID": recoveredSessionID]
            )
        }

        guard let snapshot = TrainBootstrap.sessionController.snapshot else {
            return
        }

        await TrainBootstrap.sessionController.reconcileExpiredRestTimer()

        await TrainBootstrap.sideEffects.onEnterForeground(sessionID: snapshot.session.id)
        await TrainBootstrap.sideEffects.resumePersistedSession(
            snapshot,
            restRemainingSeconds: 0
        )

        await TrainBootstrap.sessionController.syncSideEffects(restRemainingOverride: 0, force: true)

        await DiagnosticsLog.shared.record(
            category: .logger,
            level: .info,
            message: "Rest notification tap recovery finished",
            context: [
                "sessionID": snapshot.session.id,
                "restartedLiveActivity": "reconciled"
            ]
        )
    }

    static func processPendingLaunchNotificationIfNeeded() async {
        guard let sessionID = consumePendingSessionID() else { return }
        await DiagnosticsLog.shared.record(
            category: .logger,
            level: .info,
            message: "Processing pending rest notification from launch",
            context: ["sessionID": sessionID]
        )
        await handleRestNotificationTap(sessionID: sessionID)
    }

    /// Runs after scene is active so UIKit/SwiftUI CATransactions are on the main thread.
    static func processPendingIfForeground() async {
        guard AppLifecycleState.isForeground else { return }
        guard TrainBootstrap.hasCompletedLaunchRecovery else { return }
        guard !isHandlingNotification else { return }
        guard UserDefaults.standard.string(forKey: restNotificationPendingSessionIDKey) != nil else {
            return
        }

        // Let UIKit finish activation CATransaction before any tab / Observable mutation.
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(250))
        await reclaimMainThread()

        guard AppLifecycleState.isForeground else { return }
        guard let sessionID = consumePendingSessionID() else { return }
        await handleRestNotificationTap(sessionID: sessionID)
    }

    static func handleForegroundPresentation(
        categoryIdentifier: String,
        timerID: String?,
        sessionID: String?
    ) async -> UNNotificationPresentationOptions {
        let isForeground = AppLifecycleState.isForeground
        // Skip haptics while presenting; CoreHaptics during activation is a crash vector.
        if RestTimerNotificationPlanner.shouldSuppressForegroundPresentation(
            categoryIdentifier: categoryIdentifier,
            isAppForeground: isForeground
        ) {
            if let sessionID {
                await TrainBootstrap.sideEffects.notifications.cancelRestNotification(sessionID: sessionID)
            }
            return []
        }
        return [.banner, .sound]
    }

    nonisolated private static func reclaimMainThread() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}
