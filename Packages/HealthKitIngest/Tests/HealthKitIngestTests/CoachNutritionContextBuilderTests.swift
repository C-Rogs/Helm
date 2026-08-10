import Core
import Foundation
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("CoachNutritionContextBuilder")
struct CoachNutritionContextBuilderTests {
    @Test("diary block includes targets and meals")
    func diaryIncludesTargetsAndMeals() async throws {
        let store = try PersistenceStore.inMemory()
        let helmDay = HelmDay(year: 2023, month: 11, day: 15)
        let calendar = Calendar(identifier: .gregorian)
        let loggedAt = try #require(
            calendar.date(from: DateComponents(year: 2023, month: 11, day: 15, hour: 8))
        )

        try store.nutrition.upsertMeal(
            MealRecord(
                helmDay: helmDay,
                name: "Oats",
                loggedAt: loggedAt,
                bucket: .breakfast,
                energy: Energy(kilocalories: 350),
                proteinGrams: 20,
                carbohydrateGrams: 45,
                fatGrams: 8,
                source: .quickAdd
            )
        )

        let block = await CoachNutritionContextBuilder.diaryBlock(
            from: store,
            for: helmDay,
            prescriptionSummary: nil,
            calendar: calendar,
            now: loggedAt
        )

        #expect(block.contains("targets_kcal="))
        #expect(block.contains("breakfast:"))
        #expect(block.contains("Oats"))
        #expect(block.contains("logged_kcal=350"))
    }

    @Test("diary block includes active energy when present")
    func diaryIncludesActiveEnergy() async throws {
        let store = try PersistenceStore.inMemory()
        try store.trainingPlan.save(.default)

        let calendar = Calendar(identifier: .gregorian)
        let helmDay = HelmDay(year: 2023, month: 11, day: 15)
        let date = try #require(
            calendar.date(from: DateComponents(year: 2023, month: 11, day: 15, hour: 8))
        )

        try store.dailyMetrics.upsert(
            DailyMetrics(helmDay: helmDay, activeEnergy: Energy(kilocalories: 420))
        )

        let block = await CoachNutritionContextBuilder.diaryBlock(
            from: store,
            for: helmDay,
            prescriptionSummary: nil,
            calendar: calendar,
            now: date
        )

        #expect(block.contains("active_energy_kcal=420"))
        #expect(block.contains("active_energy_freshness=fresh"))
        #expect(!block.contains("active_energy_note="))
    }

    @Test("diary block marks active energy unavailable when none stored")
    func diaryMarksActiveEnergyUnavailable() async throws {
        let store = try PersistenceStore.inMemory()
        try store.trainingPlan.save(.default)

        let calendar = Calendar(identifier: .gregorian)
        let helmDay = HelmDay(year: 2023, month: 11, day: 15)
        let date = try #require(
            calendar.date(from: DateComponents(year: 2023, month: 11, day: 15, hour: 8))
        )

        let block = await CoachNutritionContextBuilder.diaryBlock(
            from: store,
            for: helmDay,
            prescriptionSummary: nil,
            calendar: calendar,
            now: date
        )

        #expect(block.contains("active_energy_freshness=unavailable"))
        #expect(!block.contains("active_energy_kcal="))
        #expect(!block.contains("adjusted_target_kcal="))
    }
}
