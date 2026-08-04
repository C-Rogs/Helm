import Foundation
import HealthKit

/// Receives HealthKit mirrored workout sessions from Watch and publishes live HR into
/// `WatchSessionCoordinator`. Register at launch so background wake can adopt the session.
@MainActor
final class MirroredWorkoutSessionBridge: NSObject {
    static let shared = MirroredWorkoutSessionBridge()

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    func start() {
        healthStore.workoutSessionMirroringStartHandler = { [weak self] mirroredSession in
            Task { @MainActor in
                self?.adopt(mirroredSession)
            }
        }
    }

    private func adopt(_ mirroredSession: HKWorkoutSession) {
        session = mirroredSession
        mirroredSession.delegate = self

        let workoutBuilder = mirroredSession.associatedWorkoutBuilder()
        workoutBuilder.delegate = self
        builder = workoutBuilder

        WatchReadinessBootstrap.coordinator.recordDiagnostic(
            .phoneDiagnosticRelay,
            detail: "mirror.adopt state=\(mirroredSession.state.rawValue)"
        )
        // Do not mark mirror-receiving until a BPM sample arrives. Premature flag
        // blocked WCSession HR fallback while phone still had no live rate.
        publishHeartRateIfAvailable()
    }

    private func clear() {
        session = nil
        builder = nil
        WatchReadinessBootstrap.coordinator.clearMirroredHeartRate()
    }

    private func publishHeartRateIfAvailable() {
        guard let builder else { return }
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              let statistics = builder.statistics(for: quantityType),
              let quantity = statistics.mostRecentQuantity()
        else { return }

        let bpm = quantity.doubleValue(for: .count().unitDivided(by: .minute()))
        WatchReadinessBootstrap.coordinator.applyMirroredHeartRate(Int(bpm.rounded()))
    }
}

extension MirroredWorkoutSessionBridge: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            if toState == .ended || toState == .stopped {
                self.clear()
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.clear()
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didDisconnectFromRemoteDeviceWithError error: (any Error)?
    ) {
        Task { @MainActor in
            // Connection drop: clear mirror flag so WCSession HR fallback can resume.
            WatchReadinessBootstrap.coordinator.clearMirroredHeartRate()
        }
    }
}

extension MirroredWorkoutSessionBridge: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        Task { @MainActor in
            self.publishHeartRateIfAvailable()
        }
    }
}
