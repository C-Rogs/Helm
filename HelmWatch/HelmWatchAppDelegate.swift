import Foundation
import HealthKit
import WatchKit

/// Receives `HKWorkoutConfiguration` from phone `startWatchApp`. Required for the Watch app to open.
final class HelmWatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            WatchWorkoutLaunchBridge.shared.receive(configuration: workoutConfiguration)
        }
    }
}
