import Core
import Foundation
import HealthKit
import OSLog
import WatchConnectivity
#if os(watchOS)
import WidgetKit
#endif

/// Carries a WCSession payload dictionary into the non-isolated WatchConnectivity callback queue.
private struct UncheckedMessageBox: @unchecked Sendable {
    let message: [String: Any]
}

#if os(watchOS)
private enum RestSuppress {
    case skip(until: Date)
    case adjust(expected: Date, until: Date)
}
#endif

@MainActor
@Observable
final class WatchSessionCoordinator: NSObject {
    enum Role {
        case phone
        case watch
    }

    private static let logger = Logger(subsystem: "com.cameronro.helm", category: "Watch")

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
    private(set) var lastHeartRateReceivedAt: Date?
    /// Seconds without a fresh HR sample before Train hides the chip (avoids stuck resting HR).
    static let liveHeartRateDisplayStaleInterval: TimeInterval = 20
    var liveHeartRateBPMForDisplay: Int? {
        guard let bpm = latestLiveHeartRateBPM, let receivedAt = lastHeartRateReceivedAt else { return nil }
        guard Date().timeIntervalSince(receivedAt) <= Self.liveHeartRateDisplayStaleInterval else { return nil }
        return bpm
    }
    var workoutCompanionActive = false
    var companionExerciseName: String?
    var companionSetNumber: Int?
    var companionSetCount: Int?
    var companionTargetSummary: String?
    var companionSessionExerciseID: String?
    var companionSetID: String?
    var companionSaveWatchWorkout = false
    /// Phone session start for late Watch adoption elapsed display.
    var companionSessionStartedAt: Date?
    /// Rest timer end for local Watch countdown. Nil when rest is not running.
    var companionRestEndsAt: Date?
    /// HealthKit activity type raw value for late Watch adoption.
    var companionActivityTypeRawValue: UInt?
    /// True while the Watch has a local HK workout (companion or Manual).
    var watchWorkoutActive = false
    /// True while phone is receiving live HR via HealthKit workout mirroring.
    var isReceivingMirroredHeartRate = false
    /// True while phone `HKWorkoutSession` is publishing AirPods (or other) live HR.
    var isReceivingPhoneHeartRate = false
    /// True while phone HR workout session is running (may still be waiting for first BPM).
    var isPhoneHeartRateSessionActive = false
    #if os(watchOS)
    /// Fires when phone activates workout companion (WCSession or hydrated context).
    var onWorkoutCompanionBecameActive: (() -> Void)?
    /// Fires when phone deactivates companion; bool = save Watch HK workout.
    var onWorkoutCompanionDeactivated: ((Bool) -> Void)?
    /// Fires on every active companion payload (re-push while session already active).
    var onWorkoutCompanionPayloadReceived: (() -> Void)?
    #endif
    #if os(iOS)
    /// Phone records Watch-relayed + local companion diagnostics into DiagnosticsLog.
    var onDiagnosticEvent: ((WatchCompanionDiagnosticEvent, String?) -> Void)?
    #endif

    let role: Role
    private struct PendingWorkoutCompanionPush: Sendable {
        let active: Bool
        let exerciseName: String?
        let setNumber: Int?
        let setCount: Int?
        let targetSummary: String?
        let sessionExerciseID: String?
        let setID: String?
        let saveWatchWorkout: Bool?
        let sessionStartedAt: Date?
        let restEndsAt: Date?
        let activityTypeRawValue: UInt?
        let helmDay: HelmDay?
    }

    private var pendingWorkoutCompanionPush: PendingWorkoutCompanionPush?
    private var lastPushedCompanionKey: WatchCompanionPushKey?
    private var nextSequence = 1
    private var lastReadinessPushAt: TimeInterval?
    private var lastLiveHeartRatePushAt: TimeInterval?
    private var isLaunchingWatchApp = false
    private var lastAcceptedByOrigin: [WatchSyncPayload.Origin: WatchSyncOriginWatermark] = [:]
    #if os(watchOS)
    private let completeSetOutbox: WatchCompleteSetOutbox = {
        let directory = (try? WatchCompleteSetOutbox.applicationSupportDirectory())
            ?? FileManager.default.temporaryDirectory
        return WatchCompleteSetOutbox(directoryURL: directory)
    }()
    /// Set IDs with unacked complete-set outbox rows (Watch UI pending state).
    private(set) var pendingCompleteSetIDs: Set<String> = []
    private var lastRestDoneEndsAt: TimeInterval?
    private var lastRestCountInSecond: Int?
    /// Ignore in-flight phone rest until skip/adjust lands (or timeout).
    private var restSuppress: RestSuppress?
    #endif

    init(role: Role) {
        self.role = role
        super.init()

        #if os(watchOS)
        refreshPendingCompleteSetIDs()
        #endif

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
        sessionStartedAt: Date? = nil,
        restEndsAt: Date? = nil,
        activityTypeRawValue: UInt? = nil,
        helmDay: HelmDay? = nil,
        force: Bool = false
    ) {
        guard role == .phone else { return }

        if !active {
            // End of companion: clear Watch flags. Keep phone BPM until phone session ends
            // so finish-chart wait / live chip are not wiped early.
            isReceivingMirroredHeartRate = false
            if !isReceivingPhoneHeartRate {
                latestLiveHeartRateBPM = nil
                lastHeartRateReceivedAt = nil
            }
            companionSessionStartedAt = nil
            companionRestEndsAt = nil
            companionActivityTypeRawValue = nil
            pendingWorkoutCompanionPush = nil
            lastPushedCompanionKey = nil
        } else {
            // New companion session: clear Watch inbound watermark so a Watch
            // process restart (sequence reset to 1) is not treated as stale.
            if !workoutCompanionActive {
                lastAcceptedByOrigin[.watch] = nil
            }
            companionSessionStartedAt = sessionStartedAt
            companionRestEndsAt = restEndsAt
            companionActivityTypeRawValue = activityTypeRawValue
            pendingWorkoutCompanionPush = PendingWorkoutCompanionPush(
                active: true,
                exerciseName: exerciseName,
                setNumber: setNumber,
                setCount: setCount,
                targetSummary: targetSummary,
                sessionExerciseID: sessionExerciseID,
                setID: setID,
                saveWatchWorkout: saveWatchWorkout,
                sessionStartedAt: sessionStartedAt,
                restEndsAt: restEndsAt,
                activityTypeRawValue: activityTypeRawValue,
                helmDay: helmDay
            )
        }

        guard activationState == .activated else { return }
        deliverWorkoutCompanionPush(
            active: active,
            exerciseName: exerciseName,
            setNumber: setNumber,
            setCount: setCount,
            targetSummary: targetSummary,
            sessionExerciseID: sessionExerciseID,
            setID: setID,
            saveWatchWorkout: saveWatchWorkout,
            sessionStartedAt: sessionStartedAt,
            restEndsAt: restEndsAt,
            activityTypeRawValue: activityTypeRawValue,
            helmDay: helmDay,
            force: force
        )
    }

    /// Re-delivers the last active companion push (activation/reachability recovery).
    func flushPendingWorkoutCompanionPushIfNeeded() {
        guard role == .phone else { return }
        guard activationState == .activated else { return }
        guard let pending = pendingWorkoutCompanionPush, pending.active else { return }
        deliverWorkoutCompanionPush(
            active: pending.active,
            exerciseName: pending.exerciseName,
            setNumber: pending.setNumber,
            setCount: pending.setCount,
            targetSummary: pending.targetSummary,
            sessionExerciseID: pending.sessionExerciseID,
            setID: pending.setID,
            saveWatchWorkout: pending.saveWatchWorkout,
            sessionStartedAt: pending.sessionStartedAt,
            restEndsAt: pending.restEndsAt,
            activityTypeRawValue: pending.activityTypeRawValue,
            helmDay: pending.helmDay,
            force: true
        )
    }

    private func deliverWorkoutCompanionPush(
        active: Bool,
        exerciseName: String?,
        setNumber: Int?,
        setCount: Int?,
        targetSummary: String?,
        sessionExerciseID: String?,
        setID: String?,
        saveWatchWorkout: Bool?,
        sessionStartedAt: Date?,
        restEndsAt: Date?,
        activityTypeRawValue: UInt?,
        helmDay: HelmDay?,
        force: Bool
    ) {
        let key = WatchCompanionPushKey(
            active: active,
            exerciseName: exerciseName,
            setNumber: setNumber,
            setCount: setCount,
            targetSummary: targetSummary,
            sessionExerciseID: sessionExerciseID,
            setID: setID,
            restEndsAt: restEndsAt?.timeIntervalSince1970,
            activityTypeRawValue: activityTypeRawValue
        )
        if !force, lastPushedCompanionKey == key {
            return
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
            companionSaveWatchWorkout: active ? nil : (saveWatchWorkout ?? false),
            companionSessionStartedAt: sessionStartedAt?.timeIntervalSince1970,
            companionRestEndsAt: restEndsAt?.timeIntervalSince1970,
            companionActivityTypeRawValue: activityTypeRawValue
        )
        push(payload)
        lastPushedCompanionKey = key
        guard active else { return }
        recordDiagnostic(
            .phoneCompanionPush,
            detail: "active=true exercise=\(exerciseName ?? "nil") set=\(setNumber.map(String.init) ?? "nil") reachable=\(WCSession.default.isReachable)"
        )
        let session = WCSession.default
        let message = payload.applicationContext()
        guard !message.isEmpty else {
            lastError = "Could not encode sync payload"
            return
        }
        deliverGuaranteed(message, via: session)
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

    /// Wakes Watch workout app via HealthKit. Single best-effort `startWatchApp`.
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
            recordDiagnostic(
                .phoneLaunchAttempt,
                detail: "attempt=\(attempt) reachable=\(isReachable) paired=\(isPaired) installed=\(isWatchAppInstalled)"
            )
            let (ok, message) = await startWatchAppOnce()
            recordDiagnostic(
                .phoneLaunchResult,
                detail: "attempt=\(attempt) ok=\(ok) error=\(message ?? "none")"
            )
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
            try? await Task.sleep(for: .seconds(WatchWorkoutLaunchPolicy.retryDelaySeconds))
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
        let kind = pendingWorkoutCompanionPush.flatMap { pending in
            pending.activityTypeRawValue.map(WatchWorkoutActivityKind.fromHealthKitActivityTypeRawValue)
        } ?? .traditionalStrengthTraining
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = HKWorkoutActivityType(rawValue: kind.healthKitActivityTypeRawValue)
            ?? .traditionalStrengthTraining
        configuration.locationType = kind.usesOutdoorLocation ? .outdoor : .indoor
        return await withCheckedContinuation { continuation in
            HKHealthStore().startWatchApp(with: configuration) { @Sendable (success: Bool, error: Error?) in
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

    /// Local OSLog + phone DiagnosticsLog (and Watch→phone relay when on Watch).
    func recordDiagnostic(_ event: WatchCompanionDiagnosticEvent, detail: String? = nil) {
        let detailText = detail ?? ""
        if detailText.isEmpty {
            Self.logger.info("\(event.rawValue, privacy: .public)")
        } else {
            Self.logger.info("\(event.rawValue, privacy: .public) \(detailText, privacy: .public)")
        }
        #if os(iOS)
        onDiagnosticEvent?(event, detail)
        #endif
        #if os(watchOS)
        pushDiagnosticToPhone(event: event, detail: detail)
        #endif
    }

    #if os(watchOS)
    private func pushDiagnosticToPhone(event: WatchCompanionDiagnosticEvent, detail: String?) {
        guard activationState == .activated else { return }
        let payload = makePayload(
            origin: .watch,
            messageKind: .diagnostic,
            diagnosticEvent: event.rawValue,
            diagnosticDetail: detail
        )
        let session = WCSession.default
        let message = payload.applicationContext()
        guard !message.isEmpty else { return }
        lastSent = payload
        deliverGuaranteed(message, via: session)
    }
    #endif

    func requestCompleteSet(sessionExerciseID: String, setID: String, helmDay: HelmDay? = nil) {
        guard role == .watch else { return }
        #if os(watchOS)
        // One unacked event per set; double-tap must not enqueue duplicates.
        if completeSetOutbox.hasUnacked(setID: setID) {
            flushCompleteSetOutbox(helmDay: helmDay)
            return
        }

        _ = completeSetOutbox.enqueue(
            sessionExerciseID: sessionExerciseID,
            setID: setID
        )
        refreshPendingCompleteSetIDs()
        flushCompleteSetOutbox(helmDay: helmDay)
        #endif
    }

    /// Phone confirms Watch outbox event applied (or already complete).
    func acknowledgeCompleteSet(eventID: String, helmDay: HelmDay? = nil) {
        guard role == .phone else { return }
        guard activationState == .activated else { return }
        guard !eventID.isEmpty else { return }

        let payload = makePayload(
            origin: .phone,
            messageKind: .completeSetAck,
            helmDay: helmDay,
            eventID: eventID
        )
        let session = WCSession.default
        let message = payload.applicationContext()
        guard !message.isEmpty else {
            lastError = "Could not encode complete-set ack"
            return
        }
        lastSent = payload
        lastError = nil
        deliverGuaranteed(message, via: session)
    }

    /// Re-delivers unacked Watch complete-set outbox rows.
    func flushCompleteSetOutbox(helmDay: HelmDay? = nil) {
        #if os(watchOS)
        guard role == .watch else { return }
        guard activationState == .activated else {
            lastError = "Session not activated; complete-set queued"
            return
        }

        for entry in completeSetOutbox.pending {
            let payload = makePayload(
                origin: .watch,
                messageKind: .completeSet,
                helmDay: helmDay,
                companionSessionExerciseID: entry.sessionExerciseID,
                companionSetID: entry.setID,
                eventID: entry.eventID
            )
            pushCompleteSet(payload)
            completeSetOutbox.markSent(eventID: entry.eventID)
        }
        refreshPendingCompleteSetIDs()
        #endif
    }

    #if os(watchOS)
    private func refreshPendingCompleteSetIDs() {
        let previous = pendingCompleteSetIDs
        pendingCompleteSetIDs = completeSetOutbox.unackedSetIDs()
        let acked = previous.subtracting(pendingCompleteSetIDs)
        if !acked.isEmpty {
            WatchHaptic.setAck.play()
        }
    }
    #endif

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
        sendWithQueuedFallback(message, via: session)
    }

    /// WatchConnectivity calls the error handler on its own queue, so it must not be
    /// actor-isolated: an inherited @MainActor handler traps in the Swift 6 isolation check.
    private nonisolated func sendWithQueuedFallback(_ message: [String: Any], via session: WCSession) {
        guard session.isReachable else {
            _ = session.transferUserInfo(message)
            return
        }
        let box = UncheckedMessageBox(message: message)
        session.sendMessage(message, replyHandler: nil) { @Sendable [weak self] error in
            let description = error.localizedDescription
            _ = WCSession.default.transferUserInfo(box.message)
            Task { @MainActor in
                self?.lastError = description
            }
        }
    }

    func clearLiveHeartRate() {
        latestLiveHeartRateBPM = nil
        lastHeartRateReceivedAt = nil
    }

    /// Applies live HR from HealthKit workout mirroring (preferred over WCSession).
    func applyMirroredHeartRate(_ bpm: Int) {
        guard role == .phone else { return }
        isReceivingMirroredHeartRate = true
        latestLiveHeartRateBPM = bpm
        lastHeartRateReceivedAt = Date()
    }

    func clearMirroredHeartRate() {
        isReceivingMirroredHeartRate = false
        // Keep chip if phone HKWorkoutSession is still publishing (AirPods / BLE).
        if isReceivingPhoneHeartRate { return }
        latestLiveHeartRateBPM = nil
        lastHeartRateReceivedAt = nil
    }

    /// Applies live HR from phone `HKWorkoutSession` (AirPods Pro 3 path).
    func applyPhoneHeartRate(_ bpm: Int) {
        guard role == .phone else { return }
        isReceivingPhoneHeartRate = true
        isPhoneHeartRateSessionActive = true
        latestLiveHeartRateBPM = bpm
        lastHeartRateReceivedAt = Date()
    }

    func clearPhoneHeartRate() {
        if isReceivingPhoneHeartRate {
            latestLiveHeartRateBPM = nil
            lastHeartRateReceivedAt = nil
        }
        isReceivingPhoneHeartRate = false
        isPhoneHeartRateSessionActive = false
    }

    func setPhoneHeartRateSessionActive(_ active: Bool) {
        guard role == .phone else { return }
        isPhoneHeartRateSessionActive = active
        if !active {
            clearPhoneHeartRate()
        }
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
            liveHeartRateBPM: bpm,
            watchWorkoutActive: true
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

        // Live HR: prefer sendMessage when reachable; queue transferUserInfo as backup.
        sendWithQueuedFallback(message, via: session)
    }

    func pushWatchWorkoutActive(_ active: Bool, helmDay: HelmDay? = nil) {
        guard role == .watch else { return }
        watchWorkoutActive = active
        guard activationState == .activated else { return }

        let payload = makePayload(
            origin: .watch,
            messageKind: .liveHeartRate,
            helmDay: helmDay,
            liveHeartRateBPM: active ? latestLiveHeartRateBPM : nil,
            watchWorkoutActive: active
        )
        pushLiveHeartRatePayload(payload)
    }

    func requestRestSkip(helmDay: HelmDay? = nil) {
        guard role == .watch else { return }
        #if os(watchOS)
        companionRestEndsAt = nil
        lastRestCountInSecond = nil
        restSuppress = .skip(until: Date().addingTimeInterval(20))
        WatchHaptic.restSkip.play()
        let payload = makePayload(
            origin: .watch,
            messageKind: .restSkip,
            helmDay: helmDay
        )
        deliverRestControl(payload)
        #endif
    }

    func requestRestAdjust(deltaSeconds: Int, helmDay: HelmDay? = nil) {
        guard role == .watch else { return }
        #if os(watchOS)
        if let ends = companionRestEndsAt {
            let next = ends.addingTimeInterval(TimeInterval(deltaSeconds))
            if next <= Date() {
                requestRestSkip(helmDay: helmDay)
                return
            }
            companionRestEndsAt = next
            lastRestCountInSecond = nil
            restSuppress = .adjust(expected: next, until: Date().addingTimeInterval(8))
        }
        WatchHaptic.restAdjust.play()
        let payload = makePayload(
            origin: .watch,
            messageKind: .restAdjust,
            helmDay: helmDay,
            companionRestDeltaSeconds: deltaSeconds
        )
        deliverRestControl(payload)
        #endif
    }

    private func deliverRestControl(_ payload: WatchSyncPayload) {
        let session = WCSession.default
        let message = payload.applicationContext()
        guard !message.isEmpty else {
            lastError = "Could not encode rest control"
            return
        }
        lastSent = payload
        lastError = nil
        deliverGuaranteed(message, via: session)
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
        eventID: String? = nil,
        companionSaveWatchWorkout: Bool? = nil,
        companionSessionStartedAt: TimeInterval? = nil,
        companionRestEndsAt: TimeInterval? = nil,
        companionActivityTypeRawValue: UInt? = nil,
        watchWorkoutActive: Bool? = nil,
        companionRestDeltaSeconds: Int? = nil,
        diagnosticEvent: String? = nil,
        diagnosticDetail: String? = nil
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
            eventID: eventID,
            companionSaveWatchWorkout: companionSaveWatchWorkout,
            companionSessionStartedAt: companionSessionStartedAt,
            companionRestEndsAt: companionRestEndsAt,
            companionActivityTypeRawValue: companionActivityTypeRawValue,
            watchWorkoutActive: watchWorkoutActive,
            companionRestDeltaSeconds: companionRestDeltaSeconds,
            diagnosticEvent: diagnosticEvent,
            diagnosticDetail: diagnosticDetail
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
        // Diagnostics must not be dropped by sequence watermarks (Watch process restarts).
        if payload.messageKind == .diagnostic {
            handleDiagnosticPayload(payload)
            return
        }
        // completeSetAck must not be dropped: outbox clear depends on every eventID.
        if payload.messageKind == .completeSetAck {
            lastReceived = payload
            lastError = nil
            #if os(watchOS)
            if role == .watch, let eventID = payload.eventID, !eventID.isEmpty {
                completeSetOutbox.markAcked(eventID: eventID)
                refreshPendingCompleteSetIDs()
            }
            #endif
            return
        }
        // Rest Skip / ±15 must not be dropped by HR sequence watermarks.
        if payload.messageKind == .restSkip || payload.messageKind == .restAdjust {
            lastReceived = payload
            lastError = nil
            if role == .phone {
                postRestControlNotification(from: payload)
            }
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
        lastError = nil
        applyDisplayFields(from: payload)

        switch role {
        case .phone:
            handlePhoneReceived(payload)
        case .watch:
            handleWatchReceived(payload)
        }
    }

    private func handleDiagnosticPayload(_ payload: WatchSyncPayload) {
        guard let eventRaw = payload.diagnosticEvent,
              let event = WatchCompanionDiagnosticEvent(rawValue: eventRaw)
        else {
            return
        }
        #if os(iOS)
        onDiagnosticEvent?(event, payload.diagnosticDetail)
        Self.logger.info(
            "relay \(eventRaw, privacy: .public) \(payload.diagnosticDetail ?? "", privacy: .public)"
        )
        #endif
    }

    private func handlePhoneReceived(_ payload: WatchSyncPayload) {
        switch payload.messageKind {
        case .ping:
            roundTripComplete = payload.origin == .watch
        case .readiness, .workoutCompanion, .restEnded, .diagnostic, .completeSetAck:
            break
        case .liveHeartRate:
            // HR applied in applyDisplayFields (mirror preferred when fresh).
            break
        case .completeSet:
            postCompleteSetNotification(from: payload)
        case .restSkip, .restAdjust:
            postRestControlNotification(from: payload)
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
        case .liveHeartRate, .completeSet, .diagnostic, .restSkip, .restAdjust:
            break
        case .workoutCompanion:
            break
        case .restEnded:
            if let ends = companionRestEndsAt {
                playRestDoneIfNeeded(endsAt: ends)
            } else {
                playRestEndedHaptic()
            }
        case .completeSetAck:
            break
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
        var userInfo: [String: Any] = [
            LiveActivityCompleteSetBridge.sessionExerciseIDKey: exerciseID,
            LiveActivityCompleteSetBridge.setIDKey: setID
        ]
        if let eventID = payload.eventID, !eventID.isEmpty {
            userInfo[LiveActivityCompleteSetBridge.eventIDKey] = eventID
        }
        NotificationCenter.default.post(
            name: LiveActivityCompleteSetBridge.notificationName,
            object: nil,
            userInfo: userInfo
        )
        #endif
    }

    private func postRestControlNotification(from payload: WatchSyncPayload) {
        #if os(iOS)
        switch payload.messageKind {
        case .restSkip:
            NotificationCenter.default.post(
                name: WatchRestControlBridge.notificationName,
                object: nil,
                userInfo: [WatchRestControlBridge.actionKey: WatchRestControlBridge.skipAction]
            )
        case .restAdjust:
            guard let delta = payload.companionRestDeltaSeconds else { return }
            NotificationCenter.default.post(
                name: WatchRestControlBridge.notificationName,
                object: nil,
                userInfo: [
                    WatchRestControlBridge.actionKey: WatchRestControlBridge.adjustAction,
                    WatchRestControlBridge.deltaKey: delta
                ]
            )
        default:
            break
        }
        #endif
    }

    private func playRestEndedHaptic() {
        #if os(watchOS)
        WatchHaptic.restDone.play()
        #endif
    }

    /// Watch-local rest countdown hit zero. Dedupes against the phone `restEnded` message.
    func playRestDoneIfNeeded(endsAt: Date) {
        #if os(watchOS)
        let key = floor(endsAt.timeIntervalSince1970)
        if lastRestDoneEndsAt == key { return }
        lastRestDoneEndsAt = key
        lastRestCountInSecond = nil
        playRestEndedHaptic()
        #endif
    }

    /// Rest ticks + restDone. Safe to call every second from TimelineView.
    func tickRestHaptics(at date: Date) {
        #if os(watchOS)
        guard let ends = companionRestEndsAt else {
            lastRestCountInSecond = nil
            return
        }
        if ends <= date {
            playRestDoneIfNeeded(endsAt: ends)
            return
        }
        let remaining = max(0, Int(ceil(ends.timeIntervalSince(date))))
        guard remaining >= 1, remaining <= 5 else { return }
        if lastRestCountInSecond == remaining { return }
        lastRestCountInSecond = remaining
        WatchHaptic.restCountIn.play()
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
        persistReadinessFaceIfNeeded(from: payload)
        if let watchWorkout = payload.watchWorkoutActive {
            watchWorkoutActive = watchWorkout
        }
        if let liveHeartRateBPM = payload.liveHeartRateBPM {
            // Prefer fresh HealthKit mirror samples; otherwise accept WCSession HR.
            let preferMirror = isReceivingMirroredHeartRate && liveHeartRateBPMForDisplay != nil
            if !preferMirror {
                latestLiveHeartRateBPM = liveHeartRateBPM
                lastHeartRateReceivedAt = Date()
            }
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
            if let started = payload.companionSessionStartedAt {
                companionSessionStartedAt = Date(timeIntervalSince1970: started)
            }
            applyCompanionRest(from: payload)
            if let activity = payload.companionActivityTypeRawValue {
                companionActivityTypeRawValue = activity
            }
            if workoutCompanionActive == false {
                isReceivingMirroredHeartRate = false
                if !isReceivingPhoneHeartRate {
                    latestLiveHeartRateBPM = nil
                    lastHeartRateReceivedAt = nil
                }
                companionSessionStartedAt = nil
                companionRestEndsAt = nil
                companionActivityTypeRawValue = nil
                #if os(watchOS)
                lastRestDoneEndsAt = nil
                lastRestCountInSecond = nil
                restSuppress = nil
                #endif
            }
            #if os(watchOS)
            if isActive && !wasActive {
                onWorkoutCompanionBecameActive?()
                flushCompleteSetOutbox()
            } else if !isActive && wasActive {
                onWorkoutCompanionDeactivated?(companionSaveWatchWorkout)
            } else if isActive {
                onWorkoutCompanionPayloadReceived?()
                flushCompleteSetOutbox()
            }
            #endif
        }
    }

    private func applyCompanionRest(from payload: WatchSyncPayload) {
        let incoming = payload.companionRestEndsAt.map { Date(timeIntervalSince1970: $0) }

        #if os(watchOS)
        if applySuppressedCompanionRest(incoming) {
            return
        }
        #endif

        commitCompanionRest(incoming)
    }

    #if os(watchOS)
    /// Returns true when a local skip/adjust is still in flight (stale phone rest ignored).
    private func applySuppressedCompanionRest(_ incoming: Date?) -> Bool {
        guard let suppress = restSuppress else { return false }
        let until: Date = {
            switch suppress {
            case .skip(let deadline): deadline
            case .adjust(_, let deadline): deadline
            }
        }()
        if Date() > until {
            restSuppress = nil
            return false
        }
        switch suppress {
        case .skip:
            if incoming == nil {
                commitCompanionRest(nil)
                restSuppress = nil
            }
            return true
        case .adjust(let expected, _):
            if let incoming {
                if abs(incoming.timeIntervalSince(expected)) < 2.5 {
                    commitCompanionRest(incoming)
                    restSuppress = nil
                }
                return true
            }
            commitCompanionRest(nil)
            restSuppress = nil
            return true
        }
    }
    #endif

    private func commitCompanionRest(_ next: Date?) {
        #if os(watchOS)
        let previousKey = companionRestEndsAt.map { floor($0.timeIntervalSince1970) }
        let nextKey = next.map { floor($0.timeIntervalSince1970) }
        if previousKey != nextKey {
            lastRestCountInSecond = nil
        }
        #endif
        companionRestEndsAt = next
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

    private func persistReadinessFaceIfNeeded(from payload: WatchSyncPayload) {
        guard payload.readinessScore != nil || payload.readinessBand != nil else { return }
        #if os(watchOS)
        WatchReadinessFaceStore.save(
            score: latestReadinessScore,
            band: latestReadinessBand
        )
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
