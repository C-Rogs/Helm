import Core
import Foundation
import HealthKit
import WatchKit

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

        coordinator.onWorkoutCompanionBecameActive = {
            Task { await startCompanionWorkoutIfNeeded(playHaptic: true) }
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

    static func consumePhoneLaunchIfNeeded() async {
        guard let configuration = WatchWorkoutLaunchBridge.shared.consumePendingConfiguration() else {
            return
        }
        let kind = WatchWorkoutActivityKind.fromHealthKitActivityTypeRawValue(
            configuration.activityType.rawValue
        )
        workoutStore.selectActivity(kind)
        await startCompanionWorkoutIfNeeded(playHaptic: true)
    }

    static func startCompanionWorkoutIfNeeded(playHaptic: Bool) async {
        guard workoutStore.phase == .idle || workoutStore.phase == .ended else { return }
        if playHaptic {
            WKInterfaceDevice.current().play(.start)
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
            guard !workoutStore.isMirroringToCompanion else { return }
            let day = HelmDay.day(for: .now, calendar: .current)
            coordinator.pushLiveHeartRate(Int(bpm.rounded()), helmDay: day)
        }
    }

    static func flushLiveHeartRateIfNeeded() {
        guard !workoutStore.isMirroringToCompanion else { return }
        guard let bpm = workoutStore.heartRateBPM else { return }
        guard workoutStore.phase == .active || workoutStore.phase == .paused else { return }
        let day = HelmDay.day(for: .now, calendar: .current)
        coordinator.pushLiveHeartRate(Int(bpm.rounded()), helmDay: day, force: true)
    }
}
