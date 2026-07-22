import Foundation
import HealthKit
@testable import HealthKitIngest

final class MockHealthKitStoreClient: @unchecked Sendable, HealthKitStoreClient {
    private let lock = NSLock()
    private var available = true
    private var fetchResults: [String: AnchoredFetchResult] = [:]
    private var sampleResults: [String: [HKSample]] = [:]
    private var observerHandlers: [String: @Sendable () -> Void] = [:]
    private(set) var backgroundDeliveryCalls: [(String, HKUpdateFrequency)] = []
    private(set) var authorizationRequested = false

    func setAvailable(_ available: Bool) {
        lock.withLock { self.available = available }
    }

    func setFetchResult(_ result: AnchoredFetchResult, for sampleType: HKSampleType) {
        lock.withLock { fetchResults[sampleType.identifier] = result }
    }

    func setSampleResults(_ samples: [HKSample], for sampleType: HKSampleType) {
        lock.withLock { sampleResults[sampleType.identifier] = samples }
    }

    func triggerObserver(for sampleType: HKSampleType) {
        lock.withLock { observerHandlers[sampleType.identifier]?() }
    }

    func isHealthDataAvailable() -> Bool {
        lock.withLock { available }
    }

    func requestAuthorization(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws {
        lock.withLock { authorizationRequested = true }
    }

    func fetchSamples(
        sampleType: HKSampleType,
        predicate: NSPredicate?,
        limit: Int
    ) async throws -> [HKSample] {
        lock.withLock {
            let samples = sampleResults[sampleType.identifier] ?? []
            if samples.count <= limit {
                return samples
            }
            return Array(samples.prefix(limit))
        }
    }

    func fetchAnchored(
        sampleType: HKSampleType,
        anchor: HKQueryAnchor?
    ) async throws -> AnchoredFetchResult {
        lock.withLock {
            fetchResults[sampleType.identifier] ?? AnchoredFetchResult(
                addedSamples: [],
                deletedObjectIDs: [],
                newAnchor: anchor
            )
        }
    }

    func enableBackgroundDelivery(
        for sampleType: HKSampleType,
        frequency: HKUpdateFrequency
    ) async throws {
        lock.withLock {
            backgroundDeliveryCalls.append((sampleType.identifier, frequency))
        }
    }

    func startObserver(
        for sampleType: HKSampleType,
        handler: @escaping @Sendable () -> Void
    ) -> HKQuery {
        lock.withLock { observerHandlers[sampleType.identifier] = handler }
        return HKObserverQuery(sampleType: sampleType, predicate: nil) { _, _, _ in }
    }

    func stop(_ query: HKQuery) {}

    func saveWorkout(
        activityType: HKWorkoutActivityType,
        start: Date,
        end: Date,
        metadata: [String: any Sendable]
    ) async throws -> SavedWorkoutSample {
        lock.withLock {
            SavedWorkoutSample(
                id: UUID(),
                start: start,
                end: end,
                sourceBundleID: HealthKitIngest.defaultOwnBundleID
            )
        }
    }
}
