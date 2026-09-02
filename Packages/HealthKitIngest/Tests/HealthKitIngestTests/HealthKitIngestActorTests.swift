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

    @Test("syncNow rewinds body fat anchor when HealthKit is newer than store")
    func syncRewindsStaleBodyFatAnchor() async throws {
        let store = try PersistenceStore.inMemory()
        let mockStore = MockHealthKitStoreClient()
        let anchorDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: anchorDirectory, withIntermediateDirectories: true)

        let oldDay = HelmDay(year: 2026, month: 8, day: 10)
        let oldAt = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 8))
        )
        try store.bodyComposition.upsert(
            BodyComposition(
                helmDay: oldDay,
                mass: Mass(kilograms: 82.4),
                bodyFatPercentage: 14.2,
                measuredAt: oldAt
            )
        )

        let newAt = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 9))
        )
        let sample = HKQuantitySample(
            type: HKQuantityType(.bodyFatPercentage),
            quantity: HKQuantity(unit: .percent(), doubleValue: 14.5),
            start: newAt,
            end: newAt
        )
        mockStore.setSampleResults([sample], for: HKQuantityType(.bodyFatPercentage))
        mockStore.setFetchResult(
            AnchoredFetchResult(addedSamples: [sample], deletedObjectIDs: [], newAnchor: nil),
            for: HKQuantityType(.bodyFatPercentage)
        )

        let ingest = HealthKitIngest(
            persistence: store,
            anchorDirectoryURL: anchorDirectory,
            store: mockStore
        )
        _ = await ingest.syncNow()

        let latest = try #require(try store.bodyComposition.fetchLatestWithBodyFat(onOrBefore: HelmDay(year: 2026, month: 8, day: 31)))
        #expect(latest.bodyFatPercentage == 14.5)
        #expect(latest.helmDay == HelmDay(year: 2026, month: 8, day: 31))
    }

    @Test("syncNow ingests newest body fat when anchored query is empty")
    func syncOverlaysBodyFatWhenAnchorMisses() async throws {
        let store = try PersistenceStore.inMemory()
        let mockStore = MockHealthKitStoreClient()
        let anchorDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: anchorDirectory, withIntermediateDirectories: true)

        let oldDay = HelmDay(year: 2026, month: 8, day: 10)
        let oldAt = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 8))
        )
        try store.bodyComposition.upsert(
            BodyComposition(
                helmDay: oldDay,
                mass: Mass(kilograms: 82.4),
                bodyFatPercentage: 24.4,
                measuredAt: oldAt
            )
        )

        let newAt = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 9))
        )
        let sample = HKQuantitySample(
            type: HKQuantityType(.bodyFatPercentage),
            quantity: HKQuantity(unit: .percent(), doubleValue: 0.221),
            start: newAt,
            end: newAt
        )
        mockStore.setSampleResults([sample], for: HKQuantityType(.bodyFatPercentage))
        mockStore.setFetchResult(
            AnchoredFetchResult(addedSamples: [], deletedObjectIDs: [], newAnchor: nil),
            for: HKQuantityType(.bodyFatPercentage)
        )

        let ingest = HealthKitIngest(
            persistence: store,
            anchorDirectoryURL: anchorDirectory,
            store: mockStore
        )
        _ = await ingest.syncNow()

        let latest = try #require(
            try store.bodyComposition.fetchLatestWithBodyFat(
                onOrBefore: HelmDay(year: 2026, month: 8, day: 31)
            )
        )
        #expect(latest.bodyFatPercentage == 22.1)
        #expect(latest.helmDay == HelmDay(year: 2026, month: 8, day: 31))
    }

    @Test("liveBodyFatSummary lists HealthKit dates even when GRDB is stale")
    func liveBodyFatSummaryReportsHealthKit() async throws {
        let store = try PersistenceStore.inMemory()
        let mockStore = MockHealthKitStoreClient()
        let anchorDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: anchorDirectory, withIntermediateDirectories: true)

        let newAt = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 9))
        )
        let sample = HKQuantitySample(
            type: HKQuantityType(.bodyFatPercentage),
            quantity: HKQuantity(unit: .percent(), doubleValue: 0.221),
            start: newAt,
            end: newAt
        )
        mockStore.setSampleResults([sample], for: HKQuantityType(.bodyFatPercentage))

        let ingest = HealthKitIngest(
            persistence: store,
            anchorDirectoryURL: anchorDirectory,
            store: mockStore
        )
        let summary = await ingest.liveBodyFatSummary()
        #expect(summary.contains("hk_live"))
        #expect(summary.contains("2026-08-31"))
        #expect(summary.contains("bodyfat=22.1%"))
        let trace = await ingest.lastBodyFatQueryTrace()
        #expect(trace.hkSampleCount == 1)
        #expect(trace.newestHkDay == "2026-08-31")
        #expect(trace.storedDay == nil)
        #expect(trace.keptCount == 1)
        #expect(trace.lag == "store_empty")
        #expect(trace.stage == "live")
        let facts = await ingest.lastBodyFatLatestFacts()
        #expect(facts.hkDay == "2026-08-31")
        #expect(facts.hkPercent == 22.1)
        #expect(facts.groundedChatReply().contains("22.1%"))
        #expect(facts.groundedChatReply().contains("2026-08-31"))
    }

    @Test("body fat probe counts out-of-range HealthKit samples")
    func liveBodyFatTraceCountsOutOfRange() async throws {
        let store = try PersistenceStore.inMemory()
        let mockStore = MockHealthKitStoreClient()
        let anchorDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: anchorDirectory, withIntermediateDirectories: true)

        let newAt = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 9))
        )
        let sample = HKQuantitySample(
            type: HKQuantityType(.bodyFatPercentage),
            quantity: HKQuantity(unit: .percent(), doubleValue: 0.70),
            start: newAt,
            end: newAt
        )
        mockStore.setSampleResults([sample], for: HKQuantityType(.bodyFatPercentage))

        let ingest = HealthKitIngest(
            persistence: store,
            anchorDirectoryURL: anchorDirectory,
            store: mockStore
        )
        _ = await ingest.liveBodyFatSummary()
        let trace = await ingest.lastBodyFatQueryTrace()
        #expect(trace.hkSampleCount == 1)
        #expect(trace.keptCount == 0)
        #expect(trace.skippedOutOfRange == 1)
        #expect(trace.newestHkDay == "2026-08-31")
    }

    @Test("step ingest writes HealthKit cumulative total not the delta batch")
    func stepSyncUsesCumulativeTotal() async throws {
        let store = try PersistenceStore.inMemory()
        let mockStore = MockHealthKitStoreClient()
        let anchorDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: anchorDirectory, withIntermediateDirectories: true)

        let loggedAt = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 16))
        )
        let sample = HKQuantitySample(
            type: HKQuantityType(.stepCount),
            quantity: HKQuantity(unit: .count(), doubleValue: 67),
            start: loggedAt,
            end: loggedAt
        )
        mockStore.setFetchResult(
            AnchoredFetchResult(addedSamples: [sample], deletedObjectIDs: [], newAnchor: nil),
            for: HKQuantityType(.stepCount)
        )
        mockStore.setCumulativeSum(12_320, identifier: .stepCount)

        let ingest = HealthKitIngest(
            persistence: store,
            anchorDirectoryURL: anchorDirectory,
            store: mockStore
        )
        _ = await ingest.syncKinds([.stepCount])

        let metrics = try store.dailyMetrics.fetch(helmDay: day)
        #expect(metrics?.stepCount == 12_320)
    }
}
