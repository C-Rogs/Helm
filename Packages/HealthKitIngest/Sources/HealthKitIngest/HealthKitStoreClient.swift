import Foundation
import HealthKit

public struct AnchoredFetchResult: Sendable {
    public let addedSamples: [HKSample]
    public let deletedObjectIDs: [UUID]
    public let newAnchor: HKQueryAnchor?

    public init(addedSamples: [HKSample], deletedObjectIDs: [UUID], newAnchor: HKQueryAnchor?) {
        self.addedSamples = addedSamples
        self.deletedObjectIDs = deletedObjectIDs
        self.newAnchor = newAnchor
    }
}

public protocol HealthKitStoreClient: Sendable {
    func isHealthDataAvailable() -> Bool
    func requestAuthorization(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws
    func fetchSamples(
        sampleType: HKSampleType,
        predicate: NSPredicate?,
        limit: Int
    ) async throws -> [HKSample]
    func fetchAnchored(
        sampleType: HKSampleType,
        anchor: HKQueryAnchor?
    ) async throws -> AnchoredFetchResult
    func enableBackgroundDelivery(
        for sampleType: HKSampleType,
        frequency: HKUpdateFrequency
    ) async throws
    func startObserver(
        for sampleType: HKSampleType,
        handler: @escaping @Sendable () -> Void
    ) -> HKQuery
    func stop(_ query: HKQuery)
    func saveWorkout(
        activityType: HKWorkoutActivityType,
        start: Date,
        end: Date,
        metadata: [String: any Sendable]
    ) async throws -> SavedWorkoutSample
}

public struct LiveHealthKitStore: HealthKitStoreClient {
    private let store: HKHealthStore

    public init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    public func isHealthDataAvailable() -> Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    public func requestAuthorization(
        toShare: Set<HKSampleType>,
        read: Set<HKObjectType>
    ) async throws {
        try await store.requestAuthorization(toShare: toShare, read: read)
    }

    public func fetchSamples(
        sampleType: HKSampleType,
        predicate: NSPredicate?,
        limit: Int
    ) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples ?? [])
            }
            store.execute(query)
        }
    }

    public func fetchAnchored(
        sampleType: HKSampleType,
        anchor: HKQueryAnchor?
    ) async throws -> AnchoredFetchResult {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: sampleType,
                predicate: nil,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, added, deleted, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let deletedIDs = deleted?.map(\.uuid) ?? []
                continuation.resume(
                    returning: AnchoredFetchResult(
                        addedSamples: added ?? [],
                        deletedObjectIDs: deletedIDs,
                        newAnchor: newAnchor
                    )
                )
            }
            store.execute(query)
        }
    }

    public func enableBackgroundDelivery(
        for sampleType: HKSampleType,
        frequency: HKUpdateFrequency
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.enableBackgroundDelivery(for: sampleType, frequency: frequency) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: HealthKitIngestError.backgroundDeliveryFailed(sampleType.identifier)
                    )
                }
            }
        }
    }

    public func startObserver(
        for sampleType: HKSampleType,
        handler: @escaping @Sendable () -> Void
    ) -> HKQuery {
        let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { _, completionHandler, error in
            if error == nil {
                handler()
            }
            completionHandler()
        }
        store.execute(query)
        return query
    }

    public func stop(_ query: HKQuery) {
        store.stop(query)
    }

    public func saveWorkout(
        activityType: HKWorkoutActivityType,
        start: Date,
        end: Date,
        metadata: [String: any Sendable]
    ) async throws -> SavedWorkoutSample {
        let metadataDictionary = metadata.reduce(into: [String: Any]()) { result, entry in
            result[entry.key] = entry.value
        }
        let workout = HKWorkout(
            activityType: activityType,
            start: start,
            end: end,
            workoutEvents: nil,
            totalEnergyBurned: nil,
            totalDistance: nil,
            device: .local(),
            metadata: metadataDictionary
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.save(workout) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthKitIngestError.workoutWriteFailed)
                }
            }
        }

        let bundleID = workout.sourceRevision.source.bundleIdentifier
        return SavedWorkoutSample(
            id: workout.uuid,
            start: workout.startDate,
            end: workout.endDate,
            sourceBundleID: bundleID
        )
    }
}
