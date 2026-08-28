import CoachLLM
import Core
import Foundation
import NutritionKit
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("NutritionQueryService")
struct NutritionQueryServiceTests {
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

    /// Seeds weight and intake across 7 days so the engine can build a trend
    /// with estimated TDEE, trend weight, and weekly intake average.
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

    // MARK: - Today query

    @Test("today query returns targets, TDEE, and logged kcal when data is present")
    func todayReturnsTargetsTDEEAndLoggedKcal() async throws {
        let store = try PersistenceStore.inMemory()
        try store.trainingPlan.save(.default)
        try saveDefaultBodyProfile(in: store)

        let calendar = Calendar(identifier: .gregorian)
        let helmDay = HelmDay(year: 2026, month: 8, day: 25)
        try seedTrend(in: store, through: helmDay)

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

        let service = NutritionQueryService(store: store, calendar: calendar)
        let payload = NutritionQueryPayload(queryType: .today)
        let output = try await service.run(payload, now: loggedAt)

        #expect(output.contains("query=today"))
        #expect(output.contains("targets_kcal="))
        #expect(output.contains("protein_g="))
        #expect(output.contains("carbs_g="))
        #expect(output.contains("fat_g="))
        #expect(output.contains("logging_complete="))
        #expect(output.contains("estimated_tdee="))
        #expect(output.contains("trend_weight="))
        #expect(output.contains("logged_kcal="))
    }

    @Test("today query works even without body profile")
    func todayWithoutBodyProfile() async throws {
        let store = try PersistenceStore.inMemory()
        try store.trainingPlan.save(.default)

        let calendar = Calendar(identifier: .gregorian)
        let helmDay = HelmDay(year: 2026, month: 8, day: 25)
        let loggedAt = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 8))
        )

        let service = NutritionQueryService(store: store, calendar: calendar)
        let payload = NutritionQueryPayload(queryType: .today)
        let output = try await service.run(payload, now: loggedAt)

        #expect(output.contains("query=today"))
        #expect(output.contains("targets_kcal=0"))
    }

    // MARK: - Day query

    @Test("day query for a past day returns logged data with per-bucket meals")
    func dayReturnsLoggedData() async throws {
        let store = try PersistenceStore.inMemory()
        try store.trainingPlan.save(.default)
        try saveDefaultBodyProfile(in: store)

        let calendar = Calendar(identifier: .gregorian)
        let helmDay = HelmDay(year: 2026, month: 8, day: 20) // past day
        let loggedAt = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 8))
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
        try store.nutrition.upsertMeal(
            MealRecord(
                helmDay: helmDay,
                name: "Chicken Salad",
                loggedAt: loggedAt,
                bucket: .lunch,
                energy: Energy(kilocalories: 500),
                proteinGrams: 40,
                carbohydrateGrams: 30,
                fatGrams: 20,
                source: .quickAdd
            )
        )

        let futureNow = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 12))
        )

        let service = NutritionQueryService(store: store, calendar: calendar)
        let payload = NutritionQueryPayload(queryType: .day, helmDay: "2026-08-20")
        let output = try await service.run(payload, now: futureNow)

        #expect(output.contains("query=day"))
        #expect(output.contains("[past]"))
        #expect(output.contains("targets_kcal="))
        #expect(output.contains("logged_kcal="))
        #expect(output.contains("logged_protein_g="))
        #expect(output.contains("logged_carbs_g="))
        #expect(output.contains("logged_fat_g="))
        #expect(output.contains("breakfast: Oats 350kcal"))
        #expect(output.contains("lunch: Chicken Salad 500kcal"))
    }

    // MARK: - Range query

    @Test("range query returns per-day lines and averages")
    func rangeReturnsPerDayLinesAndAverages() async throws {
        let store = try PersistenceStore.inMemory()
        try store.trainingPlan.save(.default)
        try saveDefaultBodyProfile(in: store)

        let calendar = Calendar(identifier: .gregorian)
        let endDay = HelmDay(year: 2026, month: 8, day: 25)
        try seedTrend(in: store, through: endDay)

        let loggedAt = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 8))
        )

        let service = NutritionQueryService(store: store, calendar: calendar)
        let payload = NutritionQueryPayload(queryType: .range, lookbackDays: 7)
        let output = try await service.run(payload, now: loggedAt)

        #expect(output.contains("query=range"))
        #expect(output.contains("start="))
        #expect(output.contains("end="))
        #expect(output.contains("days=7"))
        #expect(output.contains("avg_kcal="))
        #expect(output.contains("logged days"))
        #expect(output.contains("estimated_tdee="))
        #expect(output.contains("trend_weight="))
        #expect(output.contains("weekly_intake_avg="))
    }

    // MARK: - Weekly budget query

    @Test("weeklyBudget query returns budget with days")
    func weeklyBudgetReturnsBudgetWithDays() async throws {
        let store = try PersistenceStore.inMemory()
        try store.trainingPlan.save(.default)
        try saveDefaultBodyProfile(in: store)

        let calendar = Calendar(identifier: .gregorian)
        let helmDay = HelmDay(year: 2026, month: 8, day: 25)
        try seedTrend(in: store, through: helmDay)

        let loggedAt = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 8))
        )

        let service = NutritionQueryService(store: store, calendar: calendar)
        let payload = NutritionQueryPayload(queryType: .weeklyBudget)
        let output = try await service.run(payload, now: loggedAt)

        #expect(output.contains("query=weeklyBudget"))
        #expect(output.contains("week_start="))
        #expect(output.contains("weekly_tgt_kcal="))
        #expect(output.contains("consumed_kcal="))
        #expect(output.contains("remaining_kcal="))
        // Per-day lines use pipe separators.
        #expect(output.contains(" | "))
    }

    @Test("weeklyBudget returns error when engine has no data")
    func weeklyBudgetWithoutBodyProfile() async throws {
        let store = try PersistenceStore.inMemory()

        let calendar = Calendar(identifier: .gregorian)
        let loggedAt = Date()
        let service = NutritionQueryService(store: store, calendar: calendar)
        let payload = NutritionQueryPayload(queryType: .weeklyBudget)
        let output = try await service.run(payload, now: loggedAt)

        #expect(output.contains("error=unavailable"))
    }

    // MARK: - parseDay

    @Test("parseDay handles nil, invalid, and valid dates")
    func parseDay() async throws {
        let store = try PersistenceStore.inMemory()
        let service = NutritionQueryService(store: store)
        let calendar = Calendar(identifier: .gregorian)
        let loggedAt = Date()

        // nil helmDay falls back to today.
        let nilOutput = try await service.run(
            NutritionQueryPayload(queryType: .day, helmDay: nil),
            now: loggedAt
        )
        #expect(nilOutput.contains("query=day"))
        #expect(nilOutput.contains(" [future]"))

        // Invalid format falls back to today.
        let invalidOutput = try await service.run(
            NutritionQueryPayload(queryType: .day, helmDay: "not-a-date"),
            now: loggedAt
        )
        #expect(invalidOutput.contains("query=day"))
        #expect(invalidOutput.contains(" [future]"))

        // Valid date works.
        let validOutput = try await service.run(
            NutritionQueryPayload(queryType: .day, helmDay: "2026-08-20"),
            now: loggedAt
        )
        #expect(validOutput.contains("2026-08-20"))
    }
}