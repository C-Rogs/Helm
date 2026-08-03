import Core
import Foundation
import HealthKit

public struct WorkoutWriteRequest: Sendable {
    public let sessionID: String
    public let startedAt: Date
    public let endedAt: Date
    public let title: String?

    public init(sessionID: String, startedAt: Date, endedAt: Date, title: String? = nil) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.title = title
    }
}

public struct SavedWorkoutSample: Sendable {
    public let id: UUID
    public let start: Date
    public let end: Date
    public let sourceBundleID: String?

    public init(id: UUID, start: Date, end: Date, sourceBundleID: String?) {
        self.id = id
        self.start = start
        self.end = end
        self.sourceBundleID = sourceBundleID
    }
}

public protocol WorkoutHealthKitWriting: Sendable {
    func saveWorkout(_ request: WorkoutWriteRequest) async throws -> SavedWorkoutSample
}

public struct WorkoutHealthKitWriter: WorkoutHealthKitWriting {
    private let store: any HealthKitStoreClient

    public init(
        store: any HealthKitStoreClient = LiveHealthKitStore(),
        ownBundleID: String = HealthKitIngest.defaultOwnBundleID
    ) {
        self.store = store
        _ = ownBundleID
    }

    public func saveWorkout(_ request: WorkoutWriteRequest) async throws -> SavedWorkoutSample {
        let energy = StrengthWorkoutEnergyEstimator.activeEnergyKilocalories(
            startedAt: request.startedAt,
            endedAt: request.endedAt
        )
        return try await store.saveWorkout(
            activityType: .traditionalStrengthTraining,
            start: request.startedAt,
            end: request.endedAt,
            totalEnergyBurnedKilocalories: energy,
            metadata: [
                HKMetadataKeyWorkoutBrandName: "Signal",
                "com.cameronro.helm.session_id": request.sessionID,
                HKMetadataKeyExternalUUID: request.sessionID
            ]
        )
    }
}

extension WorkoutHealthKitWriter {
    public static func shouldReIngest(savedWorkout: SavedWorkoutSample, ownBundleID: String) -> Bool {
        IngestSampleFilter.shouldIngest(sourceBundleID: savedWorkout.sourceBundleID, ownBundleID: ownBundleID)
    }
}
