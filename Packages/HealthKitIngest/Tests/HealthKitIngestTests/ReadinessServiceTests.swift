import Core
import Foundation
import ReadinessKit
import Testing
@testable import HealthKitIngest
@testable import Persistence

@Suite("Readiness service")
struct ReadinessServiceTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    @Test("cold start reports building baseline")
    func coldStart() async throws {
        let store = try PersistenceStore.inMemory()
        let engine = ReadinessEngine(persistence: store, calendar: calendar)
        let day = HelmDay(year: 2026, month: 7, day: 22)

        for offset in 0..<3 {
            let helmDay = day.adding(days: offset - 2, calendar: calendar)
            try store.dailyMetrics.upsert(
                DailyMetrics(
                    helmDay: helmDay,
                    hrvSDNN: DurationMs(milliseconds: 48 + offset),
                    restingHeartRate: 52
                )
            )
        }

        let state = try await engine.dashboardState(for: day)

        guard case let .buildingBaseline(validNights, message) = state else {
            Issue.record("Expected building baseline state, got \(state)")
            return
        }

        #expect(validNights == 3)
        #expect(message.contains("3/4"))
    }

    @Test("compute persists daily score")
    func computePersistsScore() async throws {
        let store = try PersistenceStore.inMemory()
        let engine = ReadinessEngine(persistence: store, calendar: calendar)
        let endDay = HelmDay(year: 2026, month: 7, day: 22)

        for offset in 0..<20 {
            let helmDay = endDay.adding(days: offset - 19, calendar: calendar)
            try store.dailyMetrics.upsert(
                DailyMetrics(
                    helmDay: helmDay,
                    hrvSDNN: DurationMs(milliseconds: 50),
                    restingHeartRate: 52,
                    respiratoryRate: 14.0,
                    priorDayTRIMP: 40
                )
            )
            let dayStart = helmDay.startInstant(calendar: calendar)!
            let sleepStart = dayStart.addingTimeInterval(-8 * 3_600)
            let sleepEnd = sleepStart.addingTimeInterval(7.5 * 3_600)
            try store.sleep.upsert(
                SleepRecord(
                    start: sleepStart,
                    end: sleepEnd,
                    helmDay: helmDay,
                    sourceBundleID: "test"
                )
            )
        }

        let state = try await engine.dashboardState(for: endDay)

        guard case let .scored(score) = state else {
            Issue.record("Expected scored state, got \(state)")
            return
        }

        #expect((30...100).contains(score.score))
        #expect(try store.readiness.fetchScoreJSON(helmDay: endDay) != nil)
    }

    @Test("cached dashboard state reads persisted score without recompute inputs")
    func cachedDashboardState() async throws {
        let store = try PersistenceStore.inMemory()
        let engine = ReadinessEngine(persistence: store, calendar: calendar)
        let day = HelmDay(year: 2026, month: 7, day: 22)

        let score = ReadinessScore(
            score: 72,
            band: .primed,
            confidence: .high,
            confidenceValue: 0.9,
            hrvBand: .typical,
            validNights: 20,
            stabilityScore: 0.8,
            contributors: ReadinessContributorBreakdown(
                zHRV: 0.1,
                zRestingHR: 0.0,
                zSleep: 0.2,
                zRespiratory: nil,
                zTemperature: nil,
                zStrain: -0.1,
                zComposite: 0.1,
                rawScore: 70,
                dampedScore: 72
            ),
            effectiveHRVMilliseconds: 55,
            restingHeartRate: 52
        )
        let json = String(data: try JSONEncoder().encode(score), encoding: .utf8)!
        try store.readiness.upsertScore(helmDay: day, scoreJSON: json)

        let cached = try await engine.cachedDashboardState(for: day)
        guard case let .scored(loaded) = cached else {
            Issue.record("Expected cached scored state, got \(String(describing: cached))")
            return
        }
        #expect(loaded.score == 72)
        #expect(loaded.band == .primed)
    }

    @Test("cached dashboard state falls back to most recent prior day")
    func cachedFallsBackToPriorDay() async throws {
        let store = try PersistenceStore.inMemory()
        let engine = ReadinessEngine(persistence: store, calendar: calendar)
        let today = HelmDay(year: 2026, month: 7, day: 22)
        let yesterday = today.adding(days: -1, calendar: calendar)

        let score = ReadinessScore(
            score: 61,
            band: .balanced,
            confidence: .medium,
            confidenceValue: 0.7,
            hrvBand: .typical,
            validNights: 14,
            stabilityScore: 0.6,
            contributors: ReadinessContributorBreakdown(
                zHRV: nil,
                zRestingHR: nil,
                zSleep: nil,
                zRespiratory: nil,
                zTemperature: nil,
                zStrain: nil,
                zComposite: nil,
                rawScore: nil,
                dampedScore: nil
            ),
            effectiveHRVMilliseconds: nil,
            restingHeartRate: nil
        )
        let json = String(data: try JSONEncoder().encode(score), encoding: .utf8)!
        try store.readiness.upsertScore(helmDay: yesterday, scoreJSON: json)

        let cached = try await engine.cachedDashboardState(for: today)
        guard case let .scored(loaded) = cached else {
            Issue.record("Expected prior-day cached score, got \(String(describing: cached))")
            return
        }
        #expect(loaded.score == 61)
    }

    @Test("hydrateFromCache paints scored state before refresh")
    @MainActor
    func hydrateFromCachePaintsScore() async throws {
        let store = try PersistenceStore.inMemory()
        let engine = ReadinessEngine(persistence: store, calendar: calendar)
        let service = ReadinessService(engine: engine)
        let day = HelmDay.day(for: Date(), cutoff: .default, calendar: .current)

        let score = ReadinessScore(
            score: 68,
            band: .primed,
            confidence: .high,
            confidenceValue: 0.85,
            hrvBand: .elevated,
            validNights: 30,
            stabilityScore: 0.75,
            contributors: ReadinessContributorBreakdown(
                zHRV: 0.5,
                zRestingHR: 0.1,
                zSleep: 0.0,
                zRespiratory: nil,
                zTemperature: nil,
                zStrain: 0.0,
                zComposite: 0.3,
                rawScore: 66,
                dampedScore: 68
            ),
            effectiveHRVMilliseconds: 60,
            restingHeartRate: 50
        )
        let json = String(data: try JSONEncoder().encode(score), encoding: .utf8)!
        try store.readiness.upsertScore(helmDay: day, scoreJSON: json)

        #expect(service.state == .loading)
        await service.hydrateFromCache()
        guard case let .scored(loaded) = service.state else {
            Issue.record("Expected hydrate to score, got \(service.state)")
            return
        }
        #expect(loaded.score == 68)
    }

    @Test("baseline seed persists after backfill window")
    func baselineSeedPersists() async throws {
        let store = try PersistenceStore.inMemory()
        let engine = ReadinessEngine(persistence: store, calendar: calendar)
        let endDay = HelmDay(year: 2026, month: 7, day: 22)

        for offset in 0..<10 {
            let helmDay = endDay.adding(days: offset - 9, calendar: calendar)
            try store.dailyMetrics.upsert(
                DailyMetrics(
                    helmDay: helmDay,
                    hrvSDNN: DurationMs(milliseconds: 48),
                    restingHeartRate: 54
                )
            )
        }

        let window = BackfillWindow(
            start: calendar.date(from: DateComponents(year: 2026, month: 7, day: 12))!,
            end: calendar.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 12))!
        )

        try await engine.seedBaselines(from: window)

        #expect(try store.readiness.fetchBaselineJSON()?.contains("seededNightCount") == true)
    }
}

private extension HelmDay {
    func adding(days: Int, calendar: Calendar) -> HelmDay {
        guard
            let start = startInstant(calendar: calendar),
            let shifted = calendar.date(byAdding: .day, value: days, to: start)
        else {
            preconditionFailure("could not shift helm day")
        }
        return HelmDay.day(for: shifted, calendar: calendar)
    }
}
