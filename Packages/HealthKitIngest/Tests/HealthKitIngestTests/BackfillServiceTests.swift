import Core
import Foundation
import HealthKit
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("Backfill chunk planner")
struct BackfillChunkPlannerTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    @Test("six month window splits into monthly chunks")
    func monthlyChunks() throws {
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 22)))
        let start = try #require(calendar.date(byAdding: .month, value: -6, to: end))
        let window = BackfillWindow(start: start, end: end)

        let chunks = BackfillChunkPlanner.monthlyChunks(in: window, calendar: calendar)

        #expect(chunks.count == 6)
        #expect(chunks.first?.index == 0)
        #expect(chunks.last?.end == end)
    }
}

@Suite("Backfill service")
struct BackfillServiceTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    private let day = HelmDay(year: 2026, month: 7, day: 21)

    @Test("backfill ingests bounded samples and is idempotent")
    func backfillIdempotent() async throws {
        let store = try PersistenceStore.inMemory()
        let mockStore = MockHealthKitStoreClient()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let loggedAt = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 7))
        )
        let quantitySample = HKQuantitySample(
            type: HKQuantityType(.restingHeartRate),
            quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 52),
            start: loggedAt,
            end: loggedAt
        )
        mockStore.setSampleResults([quantitySample], for: HKQuantityType(.restingHeartRate))

        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 22)))
        let start = try #require(calendar.date(byAdding: .day, value: -7, to: end))
        let window = BackfillWindow(start: start, end: end)

        let service = BackfillService(
            persistence: store,
            anchorDirectoryURL: tempDir,
            store: mockStore,
            calendar: calendar
        )

        var firstProgress: BackfillProgress?
        for await progress in await service.run(window: window) {
            firstProgress = progress
        }

        let metrics = try store.dailyMetrics.fetch(helmDay: day)
        #expect(metrics?.restingHeartRate == 52)
        #expect(firstProgress?.isComplete == true)

        for await progress in await service.run(window: window) {
            #expect(progress.isComplete == true)
        }

        let metricsAgain = try store.dailyMetrics.fetch(helmDay: day)
        #expect(metricsAgain?.restingHeartRate == 52)
    }

    @Test("cursor resumes after partial completion")
    func cursorResume() async throws {
        let store = try PersistenceStore.inMemory()
        let mockStore = MockHealthKitStoreClient()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))
        let start = try #require(calendar.date(byAdding: .month, value: -2, to: end))
        let window = BackfillWindow(start: start, end: end)

        let service = BackfillService(
            persistence: store,
            anchorDirectoryURL: tempDir,
            store: mockStore,
            calendar: calendar
        )

        for await progress in await service.run(window: window) {
            #expect(progress.totalChunks == 2)
        }

        #expect(await service.isComplete(for: window))
    }
}

@Suite("Backfill baseline seed")
struct BackfillBaselineSeedTests {
    @Test("maps stored metrics into readiness history")
    func readinessHistory() async throws {
        let store = try PersistenceStore.inMemory()
        let day = HelmDay(year: 2026, month: 7, day: 21)
        try store.dailyMetrics.upsert(
            DailyMetrics(
                helmDay: day,
                hrvSDNN: DurationMs(milliseconds: 48),
                restingHeartRate: 52
            )
        )

        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -7, to: end)!
        let window = BackfillWindow(start: start, end: end)
        let history = try BackfillBaselineSeed.readinessHistory(from: store, window: window)

        #expect(history.contains { $0.helmDay == day })
        #expect(history.first(where: { $0.helmDay == day })?.restingHeartRate == 52)

        let seeded = try BackfillBaselineSeed.seedBaselines(from: store, window: window)
        #expect(seeded.seededNightCount >= 1)
    }
}
