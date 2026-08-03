import Core
import Foundation
import HealthKit
import WatchConnectivity
#if os(watchOS)
import WatchKit
#endif

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
    var lastLaunchError: String?
    var latestReadinessScore: Int?
    var latestReadinessBand: String?
    var latestBriefSummary: String?
    var latestLiveHeartRateBPM: Int?
    var workoutCompanionActive = false
    var companionExerciseName: String?
    var companionSetNumber: Int?
    var companionSetCount: Int?
    var companionTargetSummary: String?
    var companionSessionExerciseID: String?
    var companionSetID: String?
    var companionSaveWatchWorkout = false
    /// True while phone is receiving live HR via HealthKit workout mirroring.
    var isReceivingMirroredHeartRate = false
    #if os(watchOS)
    /// Fires when phone activates workout companion (WCSession or hydrated context).
    var onWorkoutCompanionBecameActive: (() -> Void)?
    /// Fires when phone deactivates companion; bool = save Watch HK workout.
    var onWorkoutCompanionDeactivated: ((Bool) -> Void)?
    #endif

    let role: Role
    private var nextSequence = 1
    private var lastReadinessPushAt: TimeInterval?
    private var lastLiveHeartRatePushAt: TimeInterval?
    private var isLaunchingWatchApp = false
    private var lastAcceptedByOrigin: [WatchSyncPayload.Origin: WatchSyncOriginWatermark] = [:]

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

    func pushWorkoutCompanion(
        active: Bool,
        exerciseName: String? = nil,
        setNumber: Int? = nil,
        setCount: Int? = nil,
        targetSummary: String? = nil,
        sessionExerciseID: String? = nil,
        setID: String? = nil,
        saveWatchWorkout: Bool? = nil,
        helmDay: HelmDay? = nil
    ) {
        guard role == .phone else { return }
        guard activationState == .activated else { return }

        if !active {
            latestLiveHeartRateBPM = nil
            isReceivingMirroredHeartRate = false
        }

        let payload = makePayload(
            origin: .phone,
            messageKind: .workoutCompanion,
            helmDay: helmDay,
            workoutCompanionActive: active,
            companionExerciseName: exerciseName,
            companionSetNumber: setNumber,
            companionSetCount: setCount,
            companionTargetSummary: targetSummary,
            companionSessionExerciseID: sessionExerciseID,
            companionSetID: setID,
            companionSaveWatchWorkout: active ? nil : (saveWatchWorkout ?? false)
        )
        push(payload)
    }

    /// True when phone can drive a Watch workout companion (paired + app installed).
    var canDriveWatchCompanion: Bool {
        #if os(iOS)
        return isPaired && isWatchAppInstalled
        #else
        return true
        #endif
    }

    var isCompanionLive: Bool {
        workoutCompanionActive && isReachable && latestLiveHeartRateBPM != nil
    }

    /// Wakes Watch workout app via HealthKit. Retries only when an attempt fails.
    @discardableResult
    func launchWatchWorkoutCompanion() async -> Bool {
        guard role == .phone else { return false }
        refreshSessionFlags()
        #if os(iOS)
        guard activationState == .activated, canDriveWatchCompanion else {
            lastLaunchError = canDriveWatchCompanion
                ? "Watch session not activated"
                : "Watch not paired or app not installed"
            return false
        }
        guard !isLaunchingWatchApp else { return false }
        isLaunchingWatchApp = true
        defer { isLaunchingWatchApp = false }

        var anySuccess = false
        var lastFailure: String?
        for attempt in 1...WatchWorkoutLaunchPolicy.maxAttempts {
            guard WatchWorkoutLaunchPolicy.shouldAttempt(attemptNumber: attempt) else { break }
            let (ok, message) = await startWatchAppOnce()
            if ok {
                anySuccess = true
                lastLaunchError = nil
            } else {
                lastFailure = message
                lastLaunchError = message
                lastError = message
            }
            if !WatchWorkoutLaunchPolicy.shouldRetryAfter(
                completedAttempt: attempt,
                attemptSucceeded: ok
            ) {
                break
            }
        }
        if !anySuccess, let lastFailure {
            lastError = lastFailure
        }
        return anySuccess
        #else
        return true
        #endif
    }

    func launchWatchWorkoutCompanion(onFinished: (@MainActor () -> Void)?) {
        Task { @MainActor in
            _ = await launchWatchWorkoutCompanion()
            onFinished?()
        }
    }

    #if os(iOS)
    private func startWatchAppOnce() async -> (Bool, String?) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        return await withCheckedContinuation { continuation in
            HKHealthStore().startWatchApp(with: configuration) { (success: Bool, error: Error?) in
                if let error {
                    continuation.resume(returning: (false, error.localizedDescription))
                } else if !success {
                    continuation.resume(returning: (false, "Watch workout app failed to launch"))
                } else {
                    continuation.resume(returning: (true, nil))
                }
            }
        }
    }
    #endif

    func refreshPairingFlags() {
        refreshSessionFlags()
    }

    func requestCompleteSet(sessionExerciseID: String, setID: String, helmDay: HelmDay? = nil) {
        guard role == .watch else { return }
        guard activationState == .activated else {
            lastError = "Session not activated"
            return
        }

        let payload = makePayload(
            origin: .watch,
            messageKind: .completeSet,
            helmDay: helmDay,
            companionSessionExerciseID: sessionExerciseID,
            companionSetID: setID
        )
        pushCompleteSet(payload)
    }

    private func pushCompleteSet(_ payload: WatchSyncPayload) {
        let session = WCSession.default
        let message = payload.applicationContext()
        guard !message.isEmpty else {
            lastError = "Could not encode complete-set payload"
            return
        }

        lastSent = payload
        lastError = nil
        deliverGuaranteed(message, via: session)
    }

    /// Immediate rest-end cue for Watch haptic. Prefer sendMessage when reachable.
    func notifyRestEnded(helmDay: HelmDay? = nil) {
        guard role == .phone else { return }
        guard activationState == .activated else { return }

        let payload = makePayload(
            origin: .phone,
            messageKind: .restEnded,
            helmDay: helmDay
        )
        pushRestEnded(payload)
    }

    private func pushRestEnded(_ payload: WatchSyncPayload) {
        let session = WCSession.default
        let message = payload.applicationContext()
        guard !message.isEmpty else {
            lastError = "Could not encode rest-ended payload"
            return
        }

        lastSent = payload
        lastError = nil
        deliverGuaranteed(message, via: session)
    }

    /// Best-effort immediate delivery with queued fallback.
    private func deliverGuaranteed(_ message: [String: Any], via session: WCSession) {
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { [weak self] error in
                Task { @MainActor in
                    self?.lastError = error.localizedDescription
                    _ = session.transferUserInfo(message)
                }
            }
        } else {
            _ = session.transferUserInfo(message)
        }
    }

    func clearLiveHeartRate() {
        latestLiveHeartRateBPM = nil
    }

    /// Applies live HR from HealthKit workout mirroring (preferred over WCSession).
    func applyMirroredHeartRate(_ bpm: Int) {
        guard role == .phone else { return }
        isReceivingMirroredHeartRate = true
        latestLiveHeartRateBPM = bpm
    }

    func clearMirroredHeartRate() {
        isReceivingMirroredHeartRate = false
    }

    func pushLiveHeartRate(_ bpm: Int, helmDay: HelmDay, force: Bool = false) {
        guard role == .watch else { return }
        guard activationState == .activated else { return }

        let now = Date().timeIntervalSince1970
        if !force,
           let lastLiveHeartRatePushAt,
           now - lastLiveHeartRatePushAt < WatchSyncPayload.liveHeartRatePushThrottleInterval {
            return
        }

        let payload = makePayload(
            origin: .watch,
            messageKind: .liveHeartRate,
            helmDay: helmDay,
            liveHeartRateBPM: bpm
        )
        pushLiveHeartRatePayload(payload)
        lastLiveHeartRatePushAt = now
    }

    private func pushLiveHeartRatePayload(_ payload: WatchSyncPayload) {
        let session = WCSession.default
        let message = payload.applicationContext()
        guard !message.isEmpty else {
            lastError = "Could not encode sync payload"
            return
        }

        lastSent = payload
        lastError = nil
        applyDisplayFields(from: payload)

        // Live HR: sendMessage only when reachable. Do not hammer updateApplicationContext.
        guard session.isReachable else { return }
        session.sendMessage(message, replyHandler: nil) { [weak self] error in
            Task { @MainActor in
                self?.lastError = error.localizedDescription
            }
        }
    }

    private func makePayload(
        origin: WatchSyncPayload.Origin,
        messageKind: WatchSyncPayload.MessageKind,
        helmDay: HelmDay? = nil,
        readinessScore: Int? = nil,
        readinessBand: String? = nil,
        briefSummary: String? = nil,
        liveHeartRateBPM: Int? = nil,
        workoutCompanionActive: Bool? = nil,
        companionExerciseName: String? = nil,
        companionSetNumber: Int? = nil,
        companionSetCount: Int? = nil,
        companionTargetSummary: String? = nil,
        companionSessionExerciseID: String? = nil,
        companionSetID: String? = nil,
        companionSaveWatchWorkout: Bool? = nil
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
            liveHeartRateBPM: liveHeartRateBPM,
            workoutCompanionActive: workoutCompanionActive,
            companionExerciseName: companionExerciseName,
            companionSetNumber: companionSetNumber,
            companionSetCount: companionSetCount,
            companionTargetSummary: companionTargetSummary,
            companionSessionExerciseID: companionSessionExerciseID,
            companionSetID: companionSetID,
            companionSaveWatchWorkout: companionSaveWatchWorkout
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

    func hydrateFromReceivedApplicationContext() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard let payload = WatchSyncPayload.from(applicationContext: session.receivedApplicationContext) else {
            return
        }
        let previous = lastAcceptedByOrigin[payload.origin]
        guard WatchSyncOrdering.shouldAccept(
            sequence: payload.sequence,
            sentAt: payload.sentAt,
            previous: previous
        ) else {
            return
        }
        lastAcceptedByOrigin[payload.origin] = WatchSyncOrdering.watermark(
            sequence: payload.sequence,
            sentAt: payload.sentAt
        )
        lastReceived = payload
        applyDisplayFields(from: payload)
    }

    func handleReceived(_ payload: WatchSyncPayload) {
        let previous = lastAcceptedByOrigin[payload.origin]
        guard WatchSyncOrdering.shouldAccept(
            sequence: payload.sequence,
            sentAt: payload.sentAt,
            previous: previous
        ) else {
            return
        }
        lastAcceptedByOrigin[payload.origin] = WatchSyncOrdering.watermark(
            sequence: payload.sequence,
            sentAt: payload.sentAt
        )

        lastReceived = payload
        lastError = nil
        applyDisplayFields(from: payload)

        switch role {
        case .phone:
            handlePhoneReceived(payload)
        case .watch:
            handleWatchReceived(payload)
        }
    }

    private func handlePhoneReceived(_ payload: WatchSyncPayload) {
        switch payload.messageKind {
        case .ping:
            roundTripComplete = payload.origin == .watch
        case .readiness, .workoutCompanion, .restEnded:
            break
        case .liveHeartRate:
            // Prefer HealthKit mirroring when active; WCSession HR is fallback only.
            if !isReceivingMirroredHeartRate {
                latestLiveHeartRateBPM = payload.liveHeartRateBPM
            }
        case .completeSet:
            postCompleteSetNotification(from: payload)
        }
    }

    private func handleWatchReceived(_ payload: WatchSyncPayload) {
        switch payload.messageKind {
        case .ping:
            roundTripComplete = false
            guard payload.origin == .phone else { return }
            let reply = makePayload(origin: .watch, messageKind: .ping)
            push(reply)
            roundTripComplete = true
        case .readiness:
            roundTripComplete = false
        case .liveHeartRate, .completeSet:
            break
        case .workoutCompanion:
            break
        case .restEnded:
            playRestEndedHaptic()
        }
    }

    private func postCompleteSetNotification(from payload: WatchSyncPayload) {
        guard
            let exerciseID = payload.companionSessionExerciseID, !exerciseID.isEmpty,
            let setID = payload.companionSetID, !setID.isEmpty
        else {
            return
        }
        #if os(iOS)
        NotificationCenter.default.post(
            name: LiveActivityCompleteSetBridge.notificationName,
            object: nil,
            userInfo: [
                LiveActivityCompleteSetBridge.sessionExerciseIDKey: exerciseID,
                LiveActivityCompleteSetBridge.setIDKey: setID
            ]
        )
        #endif
    }

    private func playRestEndedHaptic() {
        #if os(watchOS)
        WKInterfaceDevice.current().play(.notification)
        #endif
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
        if let liveHeartRateBPM = payload.liveHeartRateBPM, !isReceivingMirroredHeartRate {
            latestLiveHeartRateBPM = liveHeartRateBPM
        }
        if payload.messageKind == .workoutCompanion {
            let wasActive = workoutCompanionActive
            let isActive = payload.workoutCompanionActive ?? false
            workoutCompanionActive = isActive
            companionExerciseName = payload.companionExerciseName
            companionSetNumber = payload.companionSetNumber
            companionSetCount = payload.companionSetCount
            companionTargetSummary = payload.companionTargetSummary
            companionSessionExerciseID = payload.companionSessionExerciseID
            companionSetID = payload.companionSetID
            if let save = payload.companionSaveWatchWorkout {
                companionSaveWatchWorkout = save
            }
            if workoutCompanionActive == false {
                latestLiveHeartRateBPM = nil
                isReceivingMirroredHeartRate = false
            }
            #if os(watchOS)
            if isActive && !wasActive {
                onWorkoutCompanionBecameActive?()
            } else if !isActive && wasActive {
                onWorkoutCompanionDeactivated?(companionSaveWatchWorkout)
            }
            #endif
        }
    }

    func refreshSessionFlags() {
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
