import Core
import Foundation
import HealthKit
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("HealthKit ingest actor")
struct HealthKitIngestActorTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    private let day = HelmDay(year: 2026, month: 7, day: 21)

    @Test("syncNow ingests anchored quantity samples into persistence")
    func syncQuantity() async throws {
        let store = try PersistenceStore.inMemory()
        let mockStore = MockHealthKitStoreClient()
        let anchorDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: anchorDirectory, withIntermediateDirectories: true)

        let loggedAt = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 7))
        )
        let sample = HKQuantitySample(
            type: HKQuantityType(.restingHeartRate),
            quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 54),
            start: loggedAt,
            end: loggedAt
        )
        mockStore.setFetchResult(
            AnchoredFetchResult(addedSamples: [sample], deletedObjectIDs: [], newAnchor: nil),
            for: HKQuantityType(.restingHeartRate)
        )

        let ingest = HealthKitIngest(
            persistence: store,
            anchorDirectoryURL: anchorDirectory,
            store: mockStore
        )

        let outcome = await ingest.syncNow()

        #expect(outcome.samplesIngested >= 1)
        #expect(outcome.affectedFamilies.contains(.vitals))
        let metrics = try store.dailyMetrics.fetch(helmDay: day)
        #expect(metrics?.restingHeartRate == 54)
    }

    @Test("syncNow applies anchored deletions")
    func syncDeletion() async throws {
        let store = try PersistenceStore.inMemory()
        let mockStore = MockHealthKitStoreClient()
        let anchorDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: anchorDirectory, withIntermediateDirectories: true)

        let sampleID = UUID()
        let loggedAt = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 13))
        )
        let sample = HKQuantitySample(
            type: HKQuantityType(.dietaryEnergyConsumed),
            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: 500),
            start: loggedAt,
            end: loggedAt,
            metadata: [HKMetadataKeyExternalUUID: sampleID.uuidString]
        )
        mockStore.setFetchResult(
            AnchoredFetchResult(addedSamples: [sample], deletedObjectIDs: [], newAnchor: nil),
            for: HKQuantityType(.dietaryEnergyConsumed)
        )

        let ingest = HealthKitIngest(
            persistence: store,
            anchorDirectoryURL: anchorDirectory,
            store: mockStore
        )
        _ = await ingest.syncNow()
        #expect(try store.nutrition.fetchMeals(for: day).count == 1)

        mockStore.setFetchResult(
            AnchoredFetchResult(addedSamples: [], deletedObjectIDs: [sampleID], newAnchor: nil),
            for: HKQuantityType(.dietaryEnergyConsumed)
        )
        let outcome = await ingest.syncNow()

        #expect(outcome.samplesDeleted >= 1)
        #expect(try store.nutrition.fetchMeals(for: day).isEmpty)
    }

    @Test("startObserving enables background delivery for all sample types")
    func observingSetup() async throws {
        let store = try PersistenceStore.inMemory()
        let mockStore = MockHealthKitStoreClient()
        let anchorDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: anchorDirectory, withIntermediateDirectories: true)

        let ingest = HealthKitIngest(
            persistence: store,
            anchorDirectoryURL: anchorDirectory,
            store: mockStore
        )

        await ingest.startObserving()
        let status = await ingest.currentStatus()

        #expect(status.isObserving)
        #expect(mockStore.backgroundDeliveryCalls.count == HealthKitSampleKind.allCases.count)
    }

    @Test("updates stream yields snapshot after sync")
    func updatesStream() async throws {
        let store = try PersistenceStore.inMemory()
        let mockStore = MockHealthKitStoreClient()
        let anchorDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: anchorDirectory, withIntermediateDirectories: true)

        let loggedAt = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 8))
        )
        let sample = HKQuantitySample(
            type: HKQuantityType(.heartRateVariabilitySDNN),
            quantity: HKQuantity(unit: .secondUnit(with: .milli), doubleValue: 48),
            start: loggedAt,
            end: loggedAt
        )
        mockStore.setFetchResult(
            AnchoredFetchResult(addedSamples: [sample], deletedObjectIDs: [], newAnchor: nil),
            for: HKQuantityType(.heartRateVariabilitySDNN)
        )

        let ingest = HealthKitIngest(
            persistence: store,
            anchorDirectoryURL: anchorDirectory,
            store: mockStore
        )

        let stream = ingest.updates(for: .vitals)
        var iterator = stream.makeAsyncIterator()
        let initial = await iterator.next()
        #expect(initial?.family == .vitals)

        _ = await ingest.syncNow()
        let updated = await iterator.next()
        #expect(updated?.status.lastSyncSampleCount ?? 0 >= 1)
    }
}
