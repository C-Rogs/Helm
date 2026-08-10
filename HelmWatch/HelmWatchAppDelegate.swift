import Foundation
import HealthKit
import WatchKit

/// Receives `HKWorkoutConfiguration` from phone `startWatchApp`. Required for the Watch app to open.
final class HelmWatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        // Hevy-class apps start the full HKWorkoutSession (session + builder + delegates +
        // startActivity + beginCollection) in handle before it returns. watchOS decides
        // foreground vs. background based on whether a complete workout session is active
        // when handle returns. The Task { ... } hop defers past the return, so the
        // session must be set up synchronously here.
        let sessionID = UUID().uuidString
        MainActor.assumeIsolated {
            WatchCompanionBootstrap.workoutStore.emergencyFullStart(
                configuration: workoutConfiguration,
                emergencySessionID: sessionID
            )
        }
        Task { @MainActor in
            await WatchCompanionBootstrap.handlePhoneLaunchConfiguration(workoutConfiguration)
        }
    }
}
