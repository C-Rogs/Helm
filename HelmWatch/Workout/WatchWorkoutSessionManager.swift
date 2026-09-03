import Core
import Foundation
import HealthKit

@MainActor
protocol WatchWorkoutSessionManaging: AnyObject {
    var delegate: (any WatchWorkoutSessionManagerDelegate)? { get set }
    var isMirroringToCompanion: Bool { get }
    var hasActiveSession: Bool { get }
    func requestAuthorization() async throws -> Bool
    /// Full session setup synchronously: session + builder + data source + delegates +
    /// startActivity + beginCollection. Called from `handle(_:)` before it returns.
    /// watchOS suspends cold-waked apps that don't reach a complete HKWorkoutSession
    /// before handle returns.
    func emergencyFullStart(configuration: HKWorkoutConfiguration, sessionID: String)
    func start(activity: WatchWorkoutActivityKind, sessionID: String) async throws
    func start(
        configuration: HKWorkoutConfiguration,
        sessionID: String,
        activityStart: Date?
    ) async throws
    func pause()
    func resume()
    func end(discard: Bool) async throws
}

@MainActor
protocol WatchWorkoutSessionManagerDelegate: AnyObject {
    func workoutSessionManager(
        _ manager: any WatchWorkoutSessionManaging,
        didUpdateHeartRate bpm: Double,
        restingHR: Double,
        maxHR: Double
    )
    func workoutSessionManagerDidLoseMirroring(_ manager: any WatchWorkoutSessionManaging)
    func workoutSessionManager(_ manager: any WatchWorkoutSessionManaging, didFailWithError error: Error)
}

extension WatchWorkoutSessionManagerDelegate {
    func workoutSessionManagerDidLoseMirroring(_ manager: any WatchWorkoutSessionManaging) {}
    func workoutSessionManager(_ manager: any WatchWorkoutSessionManaging, didFailWithError error: Error) {}
}

enum WatchWorkoutSessionError: LocalizedError {
    case healthKitUnavailable
    case sessionAlreadyActive
    case noActiveSession
    case builderStepFailed(String)

    var errorDescription: String? {
        switch self {
        case .healthKitUnavailable: "HealthKit is not available on this device."
        case .sessionAlreadyActive: "A workout session is already active."
        case .noActiveSession: "No active workout session."
        case let .builderStepFailed(step): "Workout builder failed during \(step)."
        }
    }
}

@MainActor
final class WatchWorkoutSessionManager: NSObject, WatchWorkoutSessionManaging {
    weak var delegate: (any WatchWorkoutSessionManagerDelegate)?
    private(set) var isMirroringToCompanion = false
    var hasActiveSession: Bool { session != nil }

    private let healthStore: HKHealthStore
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var sessionID: String?
    private var restingHR: Double = 60
    private var maxHR: Double = 185
    /// Suppresses HK `.ended` callbacks while we intentionally tear down.
    private var isEndingSession = false

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
        super.init()
    }

    func requestAuthorization() async throws -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw WatchWorkoutSessionError.healthKitUnavailable
        }

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
        await loadHeartRateBaselines()
        return true
    }

    /// Called synchronously from `handle(_:)` before it returns.
    /// Full session setup: creates session, builder, data source, delegates,
    /// starts activity, and begins collection. This is the complete HKWorkoutSession
    /// contract that watchOS requires to keep the app alive and sampling HR.
    /// `beginCollection` completion fires asynchronously -- the delegate handles it.
    func emergencyFullStart(configuration: HKWorkoutConfiguration, sessionID: String) {
        guard session == nil else { return }
        do {
            let workoutSession = try HKWorkoutSession(
                healthStore: healthStore,
                configuration: configuration
            )
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
            self.isMirroringToCompanion = false

            let startDate = Date()
            workoutSession.startActivity(with: startDate)
            workoutBuilder.beginCollection(withStart: startDate) { [weak self] _, error in
                if let error {
                    Task { @MainActor in
                        guard let self, self.session === workoutSession else { return }
                        self.delegate?.workoutSessionManager(self, didFailWithError: error)
                    }
                }
            }

            // Mirror off the critical path.
            Task { @MainActor in
                do {
                    try await workoutSession.startMirroringToCompanionDevice()
                    if self.session === workoutSession {
                        self.isMirroringToCompanion = true
                    }
                } catch {
                    if self.session === workoutSession {
                        self.isMirroringToCompanion = false
                    }
                }
            }
        } catch {
            WatchCompanionBootstrap.coordinator.recordDiagnostic(
                .watchEmergencyFail,
                detail: error.localizedDescription
            )
        }
    }

    func start(activity: WatchWorkoutActivityKind, sessionID: String) async throws {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = HKWorkoutActivityType(rawValue: activity.healthKitActivityTypeRawValue) ?? .other
        configuration.locationType = activity.usesOutdoorLocation ? .outdoor : .indoor
        try await start(configuration: configuration, sessionID: sessionID, activityStart: nil)
    }

    /// Phone `startWatchApp` / late-adoption path.
    /// `activityStart` may be in the past when Watch joins a phone session already underway.
    /// If `emergencyFullStart` already created a complete session, just sets delegates
    /// and starts mirroring (if not already started).
    func start(
        configuration: HKWorkoutConfiguration,
        sessionID: String,
        activityStart: Date?
    ) async throws {
        let workoutSession: HKWorkoutSession
        let startDate = activityStart ?? Date()

        if let existing = self.session {
            workoutSession = existing
            // Emergency session already has startActivity + beginCollection.
            // Ensure delegates are set in case emergencyFullStart was called
            // before the delegate was wired.
            if workoutSession.delegate == nil {
                workoutSession.delegate = self
            }
            if self.builder == nil {
                let workoutBuilder = workoutSession.associatedWorkoutBuilder()
                workoutBuilder.dataSource = HKLiveWorkoutDataSource(
                    healthStore: healthStore,
                    workoutConfiguration: configuration
                )
                workoutBuilder.delegate = self
                self.builder = workoutBuilder
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    workoutBuilder.beginCollection(withStart: startDate) { success, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else if success {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: WatchWorkoutSessionError.builderStepFailed("beginCollection"))
                        }
                    }
                }
            }
        } else {
            workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            workoutSession.startActivity(with: startDate)
            let workoutBuilder = workoutSession.associatedWorkoutBuilder()
            workoutBuilder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )
            workoutSession.delegate = self
            workoutBuilder.delegate = self
            self.builder = workoutBuilder
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                workoutBuilder.beginCollection(withStart: startDate) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: WatchWorkoutSessionError.builderStepFailed("beginCollection"))
                    }
                }
            }
        }

        self.session = workoutSession
        self.sessionID = sessionID

        // Mirror if not already started.
        if !isMirroringToCompanion {
            Task { @MainActor in
                do {
                    try await workoutSession.startMirroringToCompanionDevice()
                    if self.session === workoutSession {
                        self.isMirroringToCompanion = true
                    }
                } catch {
                    if self.session === workoutSession {
                        self.isMirroringToCompanion = false
                    }
                }
            }
        }
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }

    func end(discard: Bool) async throws {
        guard let session, let builder else {
            throw WatchWorkoutSessionError.noActiveSession
        }

        isEndingSession = true
        defer {
            isEndingSession = false
            self.session = nil
            self.builder = nil
            self.sessionID = nil
        }

        let endDate = Date()
        let metadata: [String: Any] = [
            HKMetadataKeyWorkoutBrandName: "Signal",
            "com.cameronro.helm.session_id": sessionID ?? "",
            HKMetadataKeyExternalUUID: sessionID ?? ""
        ]

        if isMirroringToCompanion {
            try? await session.stopMirroringToCompanionDevice()
            isMirroringToCompanion = false
        }

        for step in WatchWorkoutSessionReducer.teardownSteps(discard: discard) {
            switch step {
            case .endCollection:
                try await endCollection(builder: builder, endDate: endDate)
            case .finishWorkout:
                try await finishWorkout(builder: builder, metadata: metadata)
            case .discardWorkout:
                builder.discardWorkout()
            case .endSession:
                session.end()
            }
        }
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
                    continuation.resume(throwing: WatchWorkoutSessionError.builderStepFailed("endCollection"))
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

    private func loadHeartRateBaselines() async {
        let restingType = HKQuantityType(.restingHeartRate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let samples: [HKSample]? = try? await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: restingType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            healthStore.execute(query)
        }

        if let sample = samples?.first as? HKQuantitySample {
            restingHR = sample.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
        }
        maxHR = max(185, restingHR + 120)
    }

    private func publishHeartRate(from builder: HKLiveWorkoutBuilder) {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              let statistics = builder.statistics(for: quantityType),
              let quantity = statistics.mostRecentQuantity()
        else { return }

        let bpm = quantity.doubleValue(for: .count().unitDivided(by: .minute()))
        delegate?.workoutSessionManager(self, didUpdateHeartRate: bpm, restingHR: restingHR, maxHR: maxHR)
    }
}

extension WatchWorkoutSessionManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        guard toState == .ended || toState == .stopped else { return }
        Task { @MainActor in
            guard self.session === workoutSession, !self.isEndingSession else { return }
            let error = NSError(
                domain: "HelmWatch",
                code: Int(toState.rawValue),
                userInfo: [
                    NSLocalizedDescriptionKey: "HKWorkoutSession ended unexpectedly (\(toState.rawValue))"
                ]
            )
            self.delegate?.workoutSessionManager(self, didFailWithError: error)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.session === workoutSession, !self.isEndingSession else { return }
            self.delegate?.workoutSessionManager(self, didFailWithError: error)
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didDisconnectFromRemoteDeviceWithError error: (any Error)?
    ) {
        Task { @MainActor in
            self.isMirroringToCompanion = false
            self.delegate?.workoutSessionManagerDidLoseMirroring(self)
        }
    }
}

extension WatchWorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        Task { @MainActor in
            publishHeartRate(from: workoutBuilder)
        }
    }
}
