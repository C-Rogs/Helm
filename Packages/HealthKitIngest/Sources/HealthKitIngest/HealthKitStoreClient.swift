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
    func saveDietaryMeal(_ request: MealWriteRequest) async throws -> SavedMealSamples
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

    public func saveDietaryMeal(_ request: MealWriteRequest) async throws -> SavedMealSamples {
        let metadata: [String: Any] = [
            HKMetadataKeyExternalUUID: request.mealID,
            HelmHealthKitMetadata.mealIDKey: request.mealID,
            HelmHealthKitMetadata.mealNameKey: request.name,
            HelmHealthKitMetadata.mealSourceKey: request.mealSource
        ]

        let energyType = HKQuantityType(.dietaryEnergyConsumed)
        let proteinType = HKQuantityType(.dietaryProtein)
        let carbType = HKQuantityType(.dietaryCarbohydrates)
        let fatType = HKQuantityType(.dietaryFatTotal)

        let energySample = HKQuantitySample(
            type: energyType,
            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: request.caloriesKcal),
            start: request.loggedAt,
            end: request.loggedAt,
            device: .local(),
            metadata: metadata
        )
        let proteinSample = HKQuantitySample(
            type: proteinType,
            quantity: HKQuantity(unit: .gram(), doubleValue: request.proteinG),
            start: request.loggedAt,
            end: request.loggedAt,
            device: .local(),
            metadata: metadata
        )
        let carbSample = HKQuantitySample(
            type: carbType,
            quantity: HKQuantity(unit: .gram(), doubleValue: request.carbsG),
            start: request.loggedAt,
            end: request.loggedAt,
            device: .local(),
            metadata: metadata
        )
        let fatSample = HKQuantitySample(
            type: fatType,
            quantity: HKQuantity(unit: .gram(), doubleValue: request.fatG),
            start: request.loggedAt,
            end: request.loggedAt,
            device: .local(),
            metadata: metadata
        )

        let samples: [HKObject] = [energySample, proteinSample, carbSample, fatSample]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.save(samples) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthKitIngestError.mealWriteFailed)
                }
            }
        }

        func savedSample(from sample: HKQuantitySample) -> SavedMealSample {
            SavedMealSample(
                id: sample.uuid,
                sourceBundleID: sample.sourceRevision.source.bundleIdentifier
            )
        }

        return SavedMealSamples(
            mealID: request.mealID,
            energy: savedSample(from: energySample),
            protein: savedSample(from: proteinSample),
            carbohydrate: savedSample(from: carbSample),
            fat: savedSample(from: fatSample)
        )
    }
}
