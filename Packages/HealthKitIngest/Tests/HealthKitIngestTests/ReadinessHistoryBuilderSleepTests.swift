import Core
import Foundation
import HealthKitIngest
import Persistence
import Testing

@Suite("Readiness history sleep wiring")
struct ReadinessHistoryBuilderSleepTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    private func date(_ components: DateComponents) -> Date {
        calendar.date(from: components)!
    }

    @Test("history includes efficiency and stage minutes from persisted sleep")
    func historyIncludesSleepStages() throws {
        let store = try PersistenceStore.inMemory()
        let helmDay = HelmDay(year: 2026, month: 7, day: 24)

        try store.sleep.upsert(
            SleepRecord(
                start: date(DateComponents(year: 2026, month: 7, day: 23, hour: 23)),
                end: date(DateComponents(year: 2026, month: 7, day: 24, hour: 6)),
                helmDay: HelmDay(year: 2026, month: 7, day: 23),
                stage: .inBed
            )
        )
        try store.sleep.upsert(
            SleepRecord(
                start: date(DateComponents(year: 2026, month: 7, day: 23, hour: 23)),
                end: date(DateComponents(year: 2026, month: 7, day: 24, hour: 4, minute: 33)),
                helmDay: HelmDay(year: 2026, month: 7, day: 23),
                stage: .asleepCore
            )
        )
        try store.sleep.upsert(
            SleepRecord(
                start: date(DateComponents(year: 2026, month: 7, day: 24, hour: 2)),
                end: date(DateComponents(year: 2026, month: 7, day: 24, hour: 2, minute: 27)),
                helmDay: HelmDay(year: 2026, month: 7, day: 23),
                stage: .awake
            )
        )
        try store.sleep.upsert(
            SleepRecord(
                start: date(DateComponents(year: 2026, month: 7, day: 24, hour: 3)),
                end: date(DateComponents(year: 2026, month: 7, day: 24, hour: 4)),
                helmDay: HelmDay(year: 2026, month: 7, day: 23),
                stage: .asleepDeep
            )
        )
        try store.sleep.upsert(
            SleepRecord(
                start: date(DateComponents(year: 2026, month: 7, day: 24, hour: 4)),
                end: date(DateComponents(year: 2026, month: 7, day: 24, hour: 4, minute: 33)),
                helmDay: HelmDay(year: 2026, month: 7, day: 23),
                stage: .asleepREM
            )
        )

        let history = try ReadinessHistoryBuilder.history(
            from: store,
            from: helmDay,
            through: helmDay,
            calendar: calendar
        )

        let day = try #require(history.first { $0.helmDay == helmDay })
        #expect(abs((day.sleepDurationHours ?? 0) - 5.55) < 0.05)
        #expect(day.sleepEfficiency != nil)
        #expect(abs((day.deepSleepMinutes ?? 0) - 60) < 1)
        #expect(abs((day.remSleepMinutes ?? 0) - 33) < 1)
    }
}
