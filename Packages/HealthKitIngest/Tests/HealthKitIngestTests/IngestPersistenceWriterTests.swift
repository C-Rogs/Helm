import Core
import Foundation
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("Ingest persistence writer")
struct IngestPersistenceWriterTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    private let day = HelmDay(year: 2026, month: 7, day: 21)

    @Test("merges quantity ingest into daily metrics")
    func mergeDailyMetrics() async throws {
        let store = try PersistenceStore.inMemory()
        let writer = IngestPersistenceWriter(store: store, calendar: calendar)
        let loggedAt = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 7))
        )
        let delta = IngestDelta(
            kind: .restingHeartRate,
            addedQuantitySamples: [
                IngestQuantitySample(
                    id: UUID(),
                    start: loggedAt,
                    end: loggedAt,
                    value: 52,
                    unitSymbol: "count/min",
                    sourceBundleID: "com.apple.health"
                )
            ]
        )

        let families = try writer.apply(delta: delta)
        let metrics = try store.dailyMetrics.fetch(helmDay: day)

        #expect(families.contains(.vitals))
        #expect(metrics?.restingHeartRate == 52)
    }

    @Test("idempotent meal upsert by external sample id")
    func mealIdempotency() async throws {
        let store = try PersistenceStore.inMemory()
        let writer = IngestPersistenceWriter(store: store, calendar: calendar)
        let sampleID = UUID()
        let loggedAt = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 13))
        )
        let sample = IngestQuantitySample(
            id: sampleID,
            start: loggedAt,
            end: loggedAt,
            value: 720,
            unitSymbol: "kcal",
            sourceBundleID: "com.myfitnesspal.mfp"
        )
        let delta = IngestDelta(kind: .dietaryEnergy, addedQuantitySamples: [sample])

        _ = try writer.apply(delta: delta)
        _ = try writer.apply(delta: delta)

        let meals = try store.nutrition.fetchMeals(for: day)
        #expect(meals.count == 1)
        #expect(meals[0].externalSampleID == sampleID.uuidString.lowercased())
    }

    @Test("deletion removes meal and recomputes nutrition day")
    func mealDeletion() async throws {
        let store = try PersistenceStore.inMemory()
        let writer = IngestPersistenceWriter(store: store, calendar: calendar)
        let sampleID = UUID()
        let loggedAt = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 18))
        )
        let addDelta = IngestDelta(
            kind: .dietaryEnergy,
            addedQuantitySamples: [
                IngestQuantitySample(
                    id: sampleID,
                    start: loggedAt,
                    end: loggedAt,
                    value: 400,
                    unitSymbol: "kcal",
                    sourceBundleID: "com.myfitnesspal.mfp"
                )
            ]
        )
        _ = try writer.apply(delta: addDelta)

        let deleteDelta = IngestDelta(
            kind: .dietaryEnergy,
            deletedSampleIDs: [sampleID]
        )
        _ = try writer.apply(delta: deleteDelta)

        #expect(try store.nutrition.fetchMeals(for: day).isEmpty)
        #expect(try store.nutrition.fetchDay(helmDay: day) == nil)
    }

    @Test("sleep deletion removes stored interval")
    func sleepDeletion() async throws {
        let store = try PersistenceStore.inMemory()
        let writer = IngestPersistenceWriter(store: store, calendar: calendar)
        let sampleID = UUID()
        let start = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 23))
        )
        let end = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 6))
        )
        let addDelta = IngestDelta(
            kind: .sleep,
            addedSleepSamples: [
                IngestSleepSample(
                    id: sampleID,
                    start: start,
                    end: end,
                    stage: .asleepCore,
                    sourceBundleID: "com.apple.health"
                )
            ]
        )
        _ = try writer.apply(delta: addDelta)
        #expect(try store.sleep.fetch(id: sampleID) != nil)

        let deleteDelta = IngestDelta(kind: .sleep, deletedSampleIDs: [sampleID])
        _ = try writer.apply(delta: deleteDelta)
        #expect(try store.sleep.fetch(id: sampleID) == nil)
    }
}
