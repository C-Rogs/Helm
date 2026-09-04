import Core
import Foundation
import Persistence
import PatternKit
import Testing
@testable import HealthKitIngest

@Suite("Day feature assembler")
struct DayFeatureAssemblerTests {
    @Test("zero diet kcal is missing and alcohol uses meal source")
    func missingDietAndAlcohol() throws {
        let store = try PersistenceStore.inMemory()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!

        let dayA = HelmDay(year: 2026, month: 3, day: 10)
        let dayB = HelmDay(year: 2026, month: 3, day: 11)
        try store.dailyMetrics.upsert(
            DailyMetrics(helmDay: dayA, dietaryEnergy: Energy(kilocalories: 0), dietaryProteinGrams: 0)
        )
        try store.dailyMetrics.upsert(
            DailyMetrics(helmDay: dayB, dietaryEnergy: Energy(kilocalories: 2100), dietaryProteinGrams: 140)
        )
        try store.nutrition.upsertMeal(
            MealRecord(
                helmDay: dayA,
                name: "Wine",
                loggedAt: Date(timeIntervalSince1970: 1_741_600_000),
                energy: Energy(kilocalories: 180),
                source: .alcohol
            )
        )
        try store.nutrition.upsertMeal(
            MealRecord(
                helmDay: dayB,
                name: "Chicken",
                loggedAt: Date(timeIntervalSince1970: 1_741_700_000),
                bucket: .breakfast,
                energy: Energy(kilocalories: 500),
                source: .manual
            )
        )
        try store.nutrition.upsertDay(NutritionDay(helmDay: dayB, totalEnergy: Energy(kilocalories: 2100), totalProteinGrams: 140))

        let rows = try DayFeatureAssembler.assemble(from: store, calendar: calendar)
        let byDay = Dictionary(uniqueKeysWithValues: rows.map { ($0.helmDay, $0) })
        #expect(byDay[dayA]?.dietEnergyKcal == nil)
        #expect(byDay[dayA]?.alcohol == true)
        #expect(byDay[dayB]?.alcohol == false)
        #expect(byDay[dayB]?.breakfastLogged == true)
        #expect(byDay[dayB]?.dietEnergyKcal == 2100)
    }

    @Test("sleep lands on wake day via 18:00 window")
    func sleepWakeDay() throws {
        let store = try PersistenceStore.inMemory()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let wake = HelmDay(year: 2026, month: 7, day: 24)
        guard let wakeDate = calendar.date(from: wake.dateComponents()) else {
            Issue.record("bad date")
            return
        }
        let start = SleepAggregation.sleepWindowStart(for: wakeDate, calendar: calendar)
        let end = start.addingTimeInterval(7 * 3600)
        try store.sleep.upsert(
            SleepRecord(
                start: start.addingTimeInterval(3600),
                end: end,
                helmDay: wake,
                stage: .asleepCore
            )
        )
        let rows = try DayFeatureAssembler.assemble(from: store, calendar: calendar)
        #expect(rows.contains { $0.helmDay == wake && ($0.sleepAsleepMin ?? 0) > 300 })
    }

    @Test("duplicate same-day weights do not trap assemble")
    func duplicateWeightsSurviveAssemble() throws {
        let store = try PersistenceStore.inMemory()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let day = HelmDay(year: 2026, month: 9, day: 2)
        let measuredAt = Date(timeIntervalSince1970: 1_756_771_200)
        let lowerID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let higherID = UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!
        try store.bodyComposition.upsert(
            BodyComposition(id: lowerID, helmDay: day, mass: Mass(kilograms: 81.2), measuredAt: measuredAt)
        )
        try store.bodyComposition.upsert(
            BodyComposition(id: higherID, helmDay: day, mass: Mass(kilograms: 81.4), measuredAt: measuredAt)
        )

        let rows = try DayFeatureAssembler.assemble(from: store, calendar: calendar)
        #expect(rows.count == 1)
        #expect(rows[0].bodyMassKg == 81.4)
    }
}
