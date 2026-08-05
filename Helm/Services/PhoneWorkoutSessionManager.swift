import Core
import Foundation
import HealthKit

/// Phone-side `HKWorkoutSession` so HealthKit can feed live HR from AirPods Pro /
/// BLE heart-rate sensors during Train. Started for every session; Watch companion
/// is separate and additive.
@MainActor
final class PhoneWorkoutSessionManager: NSObject {
    static let shared = PhoneWorkoutSessionManager()

    private(set) var isActive = false

    private let healthStore: HKHealthStore
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var sessionID: String?

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
        super.init()
    }

    func start(sessionID: String, activityStart: Date?) async throws {
        guard session == nil else { return }

        guard HKHealthStore.isHealthDataAvailable() else {
            throw PhoneWorkoutSessionError.healthKitUnavailable
        }

        try await requestAuthorization()

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        let workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let workoutBuilder = workoutSession.associatedWorkoutBuilder()
        workoutBuilder.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: configuration
        )

        workoutSession.delegate = self
        workoutBuilder.delegate = self

        self.session = workoutSession
        self.builder = workoutBuilder
        self.sessionID = sessionID
        isActive = true
        WatchReadinessBootstrap.coordinator.setPhoneHeartRateSessionActive(true)

        WatchReadinessBootstrap.coordinator.recordDiagnostic(
            .phoneHeartRateSessionStart,
            detail: "sessionID=\(sessionID)"
        )

        let startDate = activityStart ?? Date()
        workoutSession.startActivity(with: startDate)

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                workoutBuilder.beginCollection(withStart: startDate) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: PhoneWorkoutSessionError.builderStepFailed("beginCollection"))
                    }
                }
            }
        } catch {
            workoutSession.end()
            self.session = nil
            self.builder = nil
            self.sessionID = nil
            isActive = false
            WatchReadinessBootstrap.coordinator.setPhoneHeartRateSessionActive(false)
            throw error
        }
    }

    /// Ends an active phone HR session. No-op when idle.
    /// - Parameter discard: true skips saving HKWorkout (no HR / user discarded).
    func end(discard: Bool) async {
        guard let session, let builder else {
            isActive = false
            return
        }

        let endDate = Date()
        let metadata: [String: Any] = [
            HKMetadataKeyWorkoutBrandName: "Signal",
            "com.cameronro.helm.session_id": sessionID ?? "",
            HKMetadataKeyExternalUUID: sessionID ?? ""
        ]

        for step in WatchWorkoutSessionReducer.teardownSteps(discard: discard) {
            switch step {
            case .endCollection:
                try? await endCollection(builder: builder, endDate: endDate)
            case .finishWorkout:
                try? await finishWorkout(builder: builder, metadata: metadata)
            case .discardWorkout:
                builder.discardWorkout()
            case .endSession:
                session.end()
            }
        }

        WatchReadinessBootstrap.coordinator.recordDiagnostic(
            .phoneHeartRateSessionEnd,
            detail: "discard=\(discard)"
        )
        WatchReadinessBootstrap.coordinator.clearPhoneHeartRate()

        self.session = nil
        self.builder = nil
        self.sessionID = nil
        isActive = false
    }

    private func requestAuthorization() async throws {
        let readTypes: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKObjectType.workoutType()
        ]
        let shareTypes: Set<HKSampleType> = [
            HKQuantityType(.heartRate),
            HKObjectType.workoutType()
        ]
        try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    private func endCollection(builder: HKLiveWorkoutBuilder, endDate: Date) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.endCollection(withEnd: endDate) { success, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == HKError.errorDomain, nsError.code == 7 {
                        continuation.resume()
                        return
                    }
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PhoneWorkoutSessionError.builderStepFailed("endCollection"))
                }
            }
        }
    }

    private func finishWorkout(builder: HKLiveWorkoutBuilder, metadata: [String: Any]) async throws {
        try await builder.addMetadata(metadata)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.finishWorkout { _, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == HKError.errorDomain, nsError.code == 7 {
                        continuation.resume()
                        return
                    }
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func publishHeartRate(from builder: HKLiveWorkoutBuilder) {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              let statistics = builder.statistics(for: quantityType),
              let quantity = statistics.mostRecentQuantity()
        else { return }

        let bpm = quantity.doubleValue(for: .count().unitDivided(by: .minute()))
        WatchReadinessBootstrap.coordinator.applyPhoneHeartRate(Int(bpm.rounded()))
    }
}

enum PhoneWorkoutSessionError: LocalizedError {
    case healthKitUnavailable
    case builderStepFailed(String)

    var errorDescription: String? {
        switch self {
        case .healthKitUnavailable: "HealthKit is not available on this device."
        case let .builderStepFailed(step): "Phone workout builder failed during \(step)."
        }
    }
}

extension PhoneWorkoutSessionManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            if toState == .ended || toState == .stopped {
                self.isActive = false
                self.session = nil
                self.builder = nil
                self.sessionID = nil
                WatchReadinessBootstrap.coordinator.clearPhoneHeartRate()
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.isActive = false
            self.session = nil
            self.builder = nil
            self.sessionID = nil
            WatchReadinessBootstrap.coordinator.clearPhoneHeartRate()
            WatchReadinessBootstrap.coordinator.recordDiagnostic(
                .phoneHeartRateSessionEnd,
                detail: "fail=\(error.localizedDescription)"
            )
        }
    }
}

extension PhoneWorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        Task { @MainActor in
            self.publishHeartRate(from: workoutBuilder)
        }
    }
}
