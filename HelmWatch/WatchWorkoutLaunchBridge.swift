import Foundation
import HealthKit

/// Bridges phone-initiated `startWatchApp` configurations into SwiftUI (`WatchRootView`).
@MainActor
final class WatchWorkoutLaunchBridge {
    static let shared = WatchWorkoutLaunchBridge()

    private(set) var pendingConfiguration: HKWorkoutConfiguration?
    var onPendingLaunch: (() -> Void)?

    func receive(configuration: HKWorkoutConfiguration) {
        pendingConfiguration = configuration
        onPendingLaunch?()
    }

    func consumePendingConfiguration() -> HKWorkoutConfiguration? {
        let configuration = pendingConfiguration
        pendingConfiguration = nil
        return configuration
    }
}
