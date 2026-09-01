import Core
import Foundation
import HealthKit

/// App-level Watch companion wiring. Must run at launch so `startWatchApp` background wake
/// can start HK + WCSession before SwiftUI appears.
@MainActor
enum WatchCompanionBootstrap {
    static let coordinator = WatchSessionCoordinator(role: .watch)
    static let workoutStore = WatchWorkoutSessionStore()

    private static var didStart = false

    static func start() {
        guard !didStart else { return }
        didStart = true
        coordinator.recordDiagnostic(.watchBootstrapStart)

        coordinator.onWorkoutCompanionBecameActive = {
            coordinator.recordDiagnostic(.watchCompanionActive, detail: "becameActive")
            Task { await startCompanionWorkoutIfNeeded(playHaptic: true) }
        }
        coordinator.onWorkoutCompanionPayloadReceived = {
            Task { await syncCompanionWorkoutWithPhoneState() }
        }
        coordinator.onWorkoutCompanionDeactivated = { saveWatchWorkout in
            Task { await handleCompanionDeactivated(saveWatchWorkout: saveWatchWorkout) }
        }

        wireHeartRatePush()

        WatchWorkoutLaunchBridge.shared.onPendingLaunch = {
            Task { await consumePhoneLaunchIfNeeded() }
        }

        coordinator.hydrateFromReceivedApplicationContext()

        Task {
            await consumePhoneLaunchIfNeeded()
            if coordinator.workoutCompanionActive {
                await startCompanionWorkoutIfNeeded(playHaptic: false)
            }
        }
    }

    /// Hevy-style cold wake: start `HKWorkoutSession` before auth / WCSession work.
    /// watchOS only keeps the app alive once a workout session is running.
    static func handlePhoneLaunchConfiguration(_ configuration: HKWorkoutConfiguration) async {
        let activity = configuration.activityType.rawValue
        coordinator.recordDiagnostic(
            .watchHandleBegin,
            detail: "activityRaw=\(activity) phase=\(String(describing: workoutStore.phase))"
        )
        start()
        WatchWorkoutLaunchBridge.shared.receive(configuration: configuration)
        await consumePhoneLaunchIfNeeded()
    }

    static func consumePhoneLaunchIfNeeded() async {
        guard let configuration = WatchWorkoutLaunchBridge.shared.consumePendingConfiguration() else {
            return
        }
        let kind = WatchWorkoutActivityKind.fromHealthKitActivityTypeRawValue(
            configuration.activityType.rawValue
        )
        workoutStore.selectActivity(kind)
        guard workoutStore.phase == .idle || workoutStore.phase == .ended else {
            coordinator.recordDiagnostic(
                .watchSessionStart,
                detail: "skip alreadyPhase=\(String(describing: workoutStore.phase))"
            )
            return
        }
        WatchHaptic.sessionStart.play()
        coordinator.recordDiagnostic(.watchSessionStart, detail: "fromPhoneConfiguration")
        await workoutStore.startWorkout(fromPhoneConfiguration: configuration)
        if workoutStore.phase == .active || workoutStore.phase == .paused {
            coordinator.recordDiagnostic(
                .watchSessionReady,
                detail: "mirroring=\(workoutStore.isMirroringToCompanion)"
            )
        } else {
            coordinator.recordDiagnostic(
                .watchSessionFail,
                detail: workoutStore.lastError ?? "phase=\(String(describing: workoutStore.phase))"
            )
        }
        flushLiveHeartRateIfNeeded()
    }

    /// Starts HK workout when phone session is active but Watch missed auto-wake (manual open, hydrate race).
    static func syncCompanionWorkoutWithPhoneState(playHaptic: Bool = false) async {
        guard coordinator.workoutCompanionActive else { return }
        await startCompanionWorkoutIfNeeded(playHaptic: playHaptic)
    }

    static func startCompanionWorkoutIfNeeded(playHaptic: Bool) async {
        guard workoutStore.phase == .idle || workoutStore.phase == .ended else { return }
        if playHaptic {
            WatchHaptic.sessionStart.play()
        }
        // Late adoption: if phone already pushed companion + start time, prefer that path.
        if coordinator.workoutCompanionActive,
           coordinator.companionSessionStartedAt != nil {
            let kind = WatchWorkoutActivityKind.fromHealthKitActivityTypeRawValue(
                coordinator.companionActivityTypeRawValue
                    ?? WatchWorkoutActivityKind.traditionalStrengthTraining.healthKitActivityTypeRawValue
            )
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = HKWorkoutActivityType(rawValue: kind.healthKitActivityTypeRawValue)
                ?? .traditionalStrengthTraining
            configuration.locationType = kind.usesOutdoorLocation ? .outdoor : .indoor
            await workoutStore.startWorkout(fromPhoneConfiguration: configuration)
            flushLiveHeartRateIfNeeded()
            return
        }
        await workoutStore.prepareHealthKit()
        await workoutStore.startWorkout()
        flushLiveHeartRateIfNeeded()
    }

    private static func handleCompanionDeactivated(saveWatchWorkout: Bool) async {
        guard workoutStore.phase == .active || workoutStore.phase == .paused else { return }
        await workoutStore.endWorkout(discard: !saveWatchWorkout)
    }

    private static func wireHeartRatePush() {
        workoutStore.onLiveHeartRateBPM = { bpm in
            guard workoutStore.phase == .active || workoutStore.phase == .paused else { return }
            // Always push WCSession HR. HealthKit mirroring can succeed on Watch while the
            // phone never receives mirror samples; WCSession is the reliable Train chip path.
            let day = HelmDay.day(for: .now, calendar: .current)
            coordinator.pushLiveHeartRate(Int(bpm.rounded()), helmDay: day)
        }
    }

    static func flushLiveHeartRateIfNeeded() {
        guard let bpm = workoutStore.heartRateBPM else { return }
        guard workoutStore.phase == .active || workoutStore.phase == .paused else { return }
        let day = HelmDay.day(for: .now, calendar: .current)
        coordinator.pushLiveHeartRate(Int(bpm.rounded()), helmDay: day, force: true)
    }
}
