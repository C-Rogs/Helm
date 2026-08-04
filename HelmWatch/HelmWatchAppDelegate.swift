import Foundation
import HealthKit
import WatchKit

/// Receives `HKWorkoutConfiguration` from phone `startWatchApp`. Required for the Watch app to open.
final class HelmWatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        // Critical path must reach HKWorkoutSession.startActivity ASAP.
        // Hevy-class apps do this in handle before auth / UI / WCSession work; otherwise
        // watchOS suspends after the notification and the app never comes to foreground.
        Task { @MainActor in
            await WatchCompanionBootstrap.handlePhoneLaunchConfiguration(workoutConfiguration)
        }
    }
}
