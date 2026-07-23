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

    static let readinessThrottleInterval = WatchSyncPayload.readinessPushThrottleInterval

    var activationState: WCSessionActivationState = .notActivated
    var isPaired = false
    var isWatchAppInstalled = false
    var isReachable = false
    var lastSent: WatchSyncPayload?
    var lastReceived: WatchSyncPayload?
    var roundTripComplete = false
    var lastError: String?
    var latestReadinessScore: Int?
    var latestReadinessBand: String?
    var latestBriefSummary: String?
    var latestLiveHeartRateBPM: Int?

    private let role: Role
    private var nextSequence = 1
    private var lastReadinessPushAt: TimeInterval?
    private var lastLiveHeartRatePushAt: TimeInterval?

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

        let payload = makePayload(
            origin: role == .phone ? .phone : .watch,
            messageKind: .ping
        )
        push(payload)
    }

    func pushReadiness(
        score: Int,
        band: String,
        helmDay: HelmDay,
        briefSummary: String?,
        force: Bool = false
    ) {
        guard role == .phone else { return }
        guard activationState == .activated else { return }

        let now = Date().timeIntervalSince1970
        if !force,
           let lastReadinessPushAt,
           now - lastReadinessPushAt < Self.readinessThrottleInterval {
            return
        }

        let payload = makePayload(
            origin: .phone,
            messageKind: .readiness,
            helmDay: helmDay,
            readinessScore: score,
            readinessBand: band,
            briefSummary: briefSummary
        )
        push(payload)
        lastReadinessPushAt = now
    }

    func pushLiveHeartRate(_ bpm: Int, helmDay: HelmDay) {
        guard role == .watch else { return }
        guard activationState == .activated else { return }

        let now = Date().timeIntervalSince1970
        if let lastLiveHeartRatePushAt,
           now - lastLiveHeartRatePushAt < WatchSyncPayload.liveHeartRatePushThrottleInterval {
            return
        }

        let payload = makePayload(
            origin: .watch,
            messageKind: .liveHeartRate,
            helmDay: helmDay,
            liveHeartRateBPM: bpm
        )
        push(payload)
        lastLiveHeartRatePushAt = now
    }

    private func makePayload(
        origin: WatchSyncPayload.Origin,
        messageKind: WatchSyncPayload.MessageKind,
        helmDay: HelmDay? = nil,
        readinessScore: Int? = nil,
        readinessBand: String? = nil,
        briefSummary: String? = nil,
        liveHeartRateBPM: Int? = nil
    ) -> WatchSyncPayload {
        let sequence = nextSequence
        nextSequence += 1
        return WatchSyncPayload(
            origin: origin,
            sequence: sequence,
            helmDay: helmDay ?? HelmDay.day(for: .now, calendar: .current),
            sentAt: Date().timeIntervalSince1970,
            messageKind: messageKind,
            readinessScore: readinessScore,
            readinessBand: readinessBand,
            briefSummary: briefSummary,
            liveHeartRateBPM: liveHeartRateBPM
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
            applyDisplayFields(from: payload)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func handleReceived(_ payload: WatchSyncPayload) {
        lastReceived = payload
        lastError = nil
        applyDisplayFields(from: payload)

        switch role {
        case .phone:
            switch payload.messageKind {
            case .ping:
                roundTripComplete = payload.origin == .watch
            case .readiness:
                break
            case .liveHeartRate:
                latestLiveHeartRateBPM = payload.liveHeartRateBPM
            }
        case .watch:
            switch payload.messageKind {
            case .ping:
                roundTripComplete = false
                guard payload.origin == .phone else { return }
                let reply = makePayload(origin: .watch, messageKind: .ping)
                push(reply)
                roundTripComplete = true
            case .readiness:
                roundTripComplete = false
            case .liveHeartRate:
                break
            }
        }
    }

    private func applyDisplayFields(from payload: WatchSyncPayload) {
        if let readinessScore = payload.readinessScore {
            latestReadinessScore = readinessScore
        }
        if let readinessBand = payload.readinessBand {
            latestReadinessBand = readinessBand
        }
        if let briefSummary = payload.briefSummary {
            latestBriefSummary = briefSummary
        }
        if let liveHeartRateBPM = payload.liveHeartRateBPM {
            latestLiveHeartRateBPM = liveHeartRateBPM
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

    func hydrateFromReceivedApplicationContext() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard let payload = WatchSyncPayload.from(applicationContext: session.receivedApplicationContext) else {
            return
        }
        lastReceived = payload
        applyDisplayFields(from: payload)
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
}
