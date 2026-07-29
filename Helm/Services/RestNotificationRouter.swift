import Diagnostics
import Foundation
import Persistence

@MainActor
enum RestNotificationRouter {
    private static let pendingSessionIDKey = "helm.pendingRestNotificationSessionID"

    static func storePendingSessionID(_ sessionID: String) {
        UserDefaults.standard.set(sessionID, forKey: pendingSessionIDKey)
    }

    static func consumePendingSessionID() -> String? {
        guard let sessionID = UserDefaults.standard.string(forKey: pendingSessionIDKey) else {
            return nil
        }
        UserDefaults.standard.removeObject(forKey: pendingSessionIDKey)
        return sessionID
    }

    static func handleRestNotificationTap(sessionID: String?) async {
        AppTabRouter.shared.openTrain()
        await TrainBootstrap.sessionController.recoverPersistedSession()
        await TrainBootstrap.sessionController.reconcileExpiredRestTimer()
        await TrainBootstrap.sessionController.syncSideEffects(restRemainingOverride: 0, force: true)

        if let sessionID {
            let activeID = TrainBootstrap.sessionController.snapshot?.session.id
            if activeID != sessionID {
                await DiagnosticsLog.shared.record(
                    category: .ui,
                    level: .info,
                    message: "Rest notification session mismatch",
                    context: ["expected": sessionID, "active": activeID ?? "none"]
                )
            }
        }
    }

    static func processPendingLaunchNotificationIfNeeded() async {
        guard let sessionID = consumePendingSessionID() else { return }
        await handleRestNotificationTap(sessionID: sessionID)
    }
}
