import Core
import Foundation
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
