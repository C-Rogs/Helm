import Diagnostics
import Foundation
import Persistence

private let restNotificationPendingSessionIDKey = "helm.pendingRestNotificationSessionID"

@MainActor
enum RestNotificationRouter {
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

        await DiagnosticsLog.shared.record(
            category: .logger,
            level: .info,
            message: "Rest notification tap recovery began",
            context: ["expectedSessionID": sessionID ?? "none"]
        )

        AppTabRouter.shared.openTrain()
        await TrainBootstrap.sessionController.recoverPersistedSession()

        let activeID = TrainBootstrap.sessionController.snapshot?.session.id
        let outcome = RestNotificationRecoveryPolicy.evaluate(
            expectedSessionID: sessionID,
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

        let shouldRestartLiveActivity = RestNotificationRecoveryPolicy.shouldRestartLiveActivity(
            hasActiveSession: true,
            hasTrackedLiveActivity: TrainBootstrap.sideEffects.liveActivity.hasTrackedActivity
        )

        if shouldRestartLiveActivity {
            await TrainBootstrap.sideEffects.resumeFromRestNotification(
                snapshot,
                restRemainingSeconds: 0
            )
        } else {
            await TrainBootstrap.sideEffects.onEnterForeground(sessionID: snapshot.session.id)
        }

        await TrainBootstrap.sessionController.syncSideEffects(restRemainingOverride: 0, force: true)

        await DiagnosticsLog.shared.record(
            category: .logger,
            level: .info,
            message: "Rest notification tap recovery finished",
            context: [
                "sessionID": snapshot.session.id,
                "restartedLiveActivity": shouldRestartLiveActivity ? "true" : "false"
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
}
