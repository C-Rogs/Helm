import Core
import Foundation
import WatchConnectivity

@MainActor
@Observable
final class WatchSessionCoordinator: NSObject {
    enum Role {
        case phone
        case watch
    }

    var activationState: WCSessionActivationState = .notActivated
    var isPaired = false
    var isWatchAppInstalled = false
    var isReachable = false
    var lastSent: WatchSyncPayload?
    var lastReceived: WatchSyncPayload?
    var roundTripComplete = false
    var lastError: String?

    private let role: Role
    private var nextSequence = 1

    init(role: Role) {
        self.role = role
        super.init()

        guard WCSession.isSupported() else {
            lastError = "WatchConnectivity unavailable"
            return
        }

        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func sendPing() {
        guard activationState == .activated else {
            lastError = "Session not activated"
            return
        }

        let payload = makePayload(origin: role == .phone ? .phone : .watch)
        push(payload)
    }

    private func makePayload(origin: WatchSyncPayload.Origin) -> WatchSyncPayload {
        let sequence = nextSequence
        nextSequence += 1
        return WatchSyncPayload(
            origin: origin,
            sequence: sequence,
            helmDay: HelmDay.day(for: .now, calendar: .current),
            sentAt: Date().timeIntervalSince1970
        )
    }

    private func push(_ payload: WatchSyncPayload) {
        let session = WCSession.default
        let context = payload.applicationContext()

        guard !context.isEmpty else {
            lastError = "Could not encode sync payload"
            return
        }

        do {
            try session.updateApplicationContext(context)
            lastSent = payload
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func handleReceived(_ payload: WatchSyncPayload) {
        lastReceived = payload
        lastError = nil

        switch role {
        case .phone:
            roundTripComplete = payload.origin == .watch
        case .watch:
            roundTripComplete = false
            guard payload.origin == .phone else { return }
            let reply = makePayload(origin: .watch)
            push(reply)
            roundTripComplete = true
        }
    }

    private func refreshSessionFlags() {
        let session = WCSession.default
        #if os(iOS)
        isPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
        #else
        isPaired = true
        isWatchAppInstalled = true
        #endif
        isReachable = session.isReachable
        activationState = session.activationState
    }
}

extension WatchSessionCoordinator: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.activationState = activationState
            self.refreshSessionFlags()

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
}
