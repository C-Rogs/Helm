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
}
