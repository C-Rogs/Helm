import Core
import Foundation
import WatchConnectivity

extension WatchSessionCoordinator: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.activationState = activationState
            self.refreshSessionFlags()
            self.hydrateFromReceivedApplicationContext()

            if let error {
                self.lastError = error.localizedDescription
                return
            }

            if self.role == .phone, activationState == .activated {
                self.sendPing()
            }
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.refreshSessionFlags()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let payload = WatchSyncPayload.from(applicationContext: applicationContext) else { return }

        Task { @MainActor in
            self.refreshSessionFlags()
            self.handleReceived(payload)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let payload = WatchSyncPayload.from(applicationContext: message) else { return }

        Task { @MainActor in
            self.refreshSessionFlags()
            self.handleReceived(payload)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let payload = WatchSyncPayload.from(applicationContext: userInfo) else { return }

        Task { @MainActor in
            self.refreshSessionFlags()
            self.handleReceived(payload)
        }
    }
}
