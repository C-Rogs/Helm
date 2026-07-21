import Core
import Foundation
import Testing
@testable import Persistence

@Suite("Health repositories")
struct HealthRepositoryTests {
    private let day = HelmDay(year: 2026, month: 7, day: 21)
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    @Test("daily metrics round trip")
    func dailyMetricsRoundTrip() throws {
        let store = try PersistenceStore.inMemory()
        let metrics = DailyMetrics(
            helmDay: day,
            hrvSDNN: DurationMs(milliseconds: 48),
            restingHeartRate: 52,
            respiratoryRate: 14.2,
            wristTemperatureDeltaCelsius: 0.3,
            activeEnergy: Energy(kilocalories: 620),
            dietaryEnergy: Energy(kilocalories: 2_450),
            dietaryProteinGrams: 185,
            dietaryCarbohydrateGrams: 240,
            dietaryFatGrams: 72,
            priorDayTRIMP: 88.5
        )

        try store.dailyMetrics.upsert(metrics)
        let fetched = try store.dailyMetrics.fetch(helmDay: day)

        #expect(fetched == metrics)
    }

    @Test("daily metrics range query")
    func dailyMetricsRange() throws {
        let store = try PersistenceStore.inMemory()
        let previous = HelmDay(year: 2026, month: 7, day: 20)
        try store.dailyMetrics.upsert(DailyMetrics(helmDay: previous, restingHeartRate: 54))
        try store.dailyMetrics.upsert(DailyMetrics(helmDay: day, restingHeartRate: 52))

        let range = try store.dailyMetrics.fetchRange(from: previous, through: day)

        #expect(range.map(\.helmDay) == [previous, day])
    }

    @Test("body composition round trip")
    func bodyCompositionRoundTrip() throws {
        let store = try PersistenceStore.inMemory()
        let measuredAt = calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 7))!
        let composition = BodyComposition(
            helmDay: day,
            mass: Mass(kilograms: 82.4),
            bodyFatPercentage: 14.2,
            measuredAt: measuredAt
        )

        try store.bodyComposition.upsert(composition)
        let fetched = try store.bodyComposition.fetch(id: composition.id)

        #expect(fetched == composition)
    }

    @Test("sleep records round trip and replace")
    func sleepRoundTrip() throws {
        let store = try PersistenceStore.inMemory()
        let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 23, minute: 15))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 6, minute: 45))!
        let record = SleepRecord(
            start: start,
            end: end,
            helmDay: day,
            sourceBundleID: "com.apple.Health"
        )

        try store.sleep.upsert(record)
        #expect(try store.sleep.fetch(for: day) == [record])

        let replacement = SleepRecord(
            start: start,
            end: end,
            helmDay: day,
            sourceBundleID: "com.apple.Health"
        )
        try store.sleep.replaceAll(for: day, records: [replacement])
        #expect(try store.sleep.fetch(for: day) == [replacement])
    }

    @Test("nutrition day and meals round trip")
    func nutritionRoundTrip() throws {
        let store = try PersistenceStore.inMemory()
        let nutritionDay = NutritionDay(
            helmDay: day,
            totalEnergy: Energy(kilocalories: 2_450),
            totalProteinGrams: 185,
            totalCarbohydrateGrams: 240,
            totalFatGrams: 72,
            macroGapKilocalories: 180
        )
        let loggedAt = calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 13))!
        let meal = MealRecord(
            helmDay: day,
            name: "Chicken rice bowl",
            loggedAt: loggedAt,
            energy: Energy(kilocalories: 720),
            proteinGrams: 52,
            carbohydrateGrams: 78,
            fatGrams: 18,
            source: .manual
        )

        try store.nutrition.upsertDay(nutritionDay)
        try store.nutrition.upsertMeal(meal)

        #expect(try store.nutrition.fetchDay(helmDay: day) == nutritionDay)
        #expect(try store.nutrition.fetchMeals(for: day) == [meal])
    }
}
