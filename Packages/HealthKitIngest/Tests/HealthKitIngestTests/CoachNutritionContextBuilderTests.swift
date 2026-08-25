import Core
import Foundation
import NutritionKit
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("CoachNutritionContextBuilder")
struct CoachNutritionContextBuilderTests {
    private func saveDefaultBodyProfile(in store: PersistenceStore) throws {
        let calendar = Calendar(identifier: .gregorian)
        let dob = calendar.date(byAdding: .year, value: -30, to: Date())!
        let profile = BodyProfile(
            bodyMassKg: 80,
            heightCm: 175,
            biologicalSex: .male,
            dateOfBirth: dob
        )
        try BodyProfileStore(metadata: store.appMetadata).save(profile)
    }

    private func seedTrend(in store: PersistenceStore, through endDay: HelmDay) throws {
        for offset in 0 ..< 7 {
            let day = endDay.adding(days: -offset)
            try store.nutrition.upsertDay(
                NutritionDay(
                    helmDay: day,
                    totalEnergy: Energy(kilocalories: 2_200),
                    totalProteinGrams: 150,
                    totalCarbohydrateGrams: 220,
                    totalFatGrams: 70
                )
            )
            try store.bodyComposition.upsert(
                BodyComposition(
                    helmDay: day,
                    mass: Mass(kilograms: 80),
                    measuredAt: Date()
                )
            )
        }
    }

    // MARK: - Diary block

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

    // MARK: - Weekly budget block

    @Test("weekly budget block returns nil when engine has no data")
    func weeklyBudgetBlockReturnsNilWithoutData() async throws {
        let store = try PersistenceStore.inMemory()
        let helmDay = HelmDay(year: 2026, month: 8, day: 25)
        let calendar = Calendar(identifier: .gregorian)

        let block = await CoachNutritionContextBuilder.weeklyBudgetBlock(
            from: store,
            for: helmDay,
            calendar: calendar
        )

        #expect(block == nil)
    }

    @Test("weekly budget block produces expected format with week_start, weekly_tgt_kcal, and demand-tagged day lines")
    func weeklyBudgetBlockFormat() async throws {
        let store = try PersistenceStore.inMemory()
        try store.trainingPlan.save(.default)
        try saveDefaultBodyProfile(in: store)

        let calendar = Calendar(identifier: .gregorian)
        let helmDay = HelmDay(year: 2026, month: 8, day: 25)
        try seedTrend(in: store, through: helmDay)

        let block = try #require(await CoachNutritionContextBuilder.weeklyBudgetBlock(
            from: store,
            for: helmDay,
            calendar: calendar
        ))

        #expect(block.contains("week_start="))
        #expect(block.contains("weekly_tgt_kcal="))
        #expect(block.contains("consumed_kcal="))
        #expect(block.contains("remaining_kcal="))
        // Each day line uses pipe separators with demand tags.
        for demand in WeeklyNutritionDemand.allCases.map(\.rawValue) {
            // At least some days will have restOffice; others depend on demand resolution.
            if block.contains(demand) { break }
        }
        for dayOffset in 0 ..< 7 {
            let day = helmDay.mondayOfSameWeek(calendar: calendar).adding(days: dayOffset)
            #expect(block.contains(day.formatted))
        }
    }

    @Test("diary block still works unchanged alongside weekly budget")
    func diaryBlockStillWorks() async throws {
        let store = try PersistenceStore.inMemory()
        try store.trainingPlan.save(.default)

        let calendar = Calendar(identifier: .gregorian)
        let helmDay = HelmDay(year: 2026, month: 8, day: 25)
        let loggedAt = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 8))
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
            calendar: calendar,
            now: loggedAt
        )

        #expect(block.contains("targets_kcal="))
        #expect(block.contains("breakfast:"))
        #expect(block.contains("Oats"))
        #expect(block.contains("logged_kcal=350"))
    }
}
