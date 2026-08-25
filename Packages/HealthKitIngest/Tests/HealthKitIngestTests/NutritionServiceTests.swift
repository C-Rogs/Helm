import Core
import Foundation
import NutritionKit
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("Nutrition service")
struct NutritionServiceTests {
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

    @Test("fixture intake renders targets vs actual with alcohol gap")
    func targetsVsActualWithGap() async throws {
        let store = try PersistenceStore.inMemory()
        try store.trainingPlan.save(.default)
        try saveDefaultBodyProfile(in: store)

        let day = HelmDay(year: 2026, month: 7, day: 23)
        let alcoholDay = NutritionDay(
            helmDay: day,
            totalEnergy: Energy(kilocalories: 2_400),
            totalProteinGrams: 150,
            totalCarbohydrateGrams: 400,
            totalFatGrams: 20,
            macroGapKilocalories: 1_120
        )
        try store.nutrition.upsertDay(alcoholDay)

        let engine = NutritionEngine(persistence: store)
        let snapshot = await engine.snapshot(for: day, prescriptionSummary: nil)

        #expect(snapshot.actual?.helmDay == alcoholDay.helmDay)
        #expect(snapshot.actual?.macroGapKilocalories != nil)
        #expect(snapshot.targets.macroGapKilocalories! > 100)
        #expect(snapshot.targets.carbohydrateGrams > 0)
        #expect(snapshot.dayType == .rest)
    }

    @Test("missing body profile yields pending macro targets")
    func pendingWithoutBodyProfile() async throws {
        let store = try PersistenceStore.inMemory()
        try store.trainingPlan.save(.default)

        let day = HelmDay(year: 2026, month: 7, day: 23)
        try store.dailyMetrics.upsert(
            DailyMetrics(
                helmDay: day,
                dietaryEnergy: Energy(kilocalories: 2_100),
                dietaryProteinGrams: 160,
                dietaryCarbohydrateGrams: 210,
                dietaryFatGrams: 60
            )
        )

        let engine = NutritionEngine(persistence: store)
        let snapshot = await engine.snapshot(for: day, prescriptionSummary: nil)

        #expect(snapshot.actual?.totalEnergy?.kilocalories == 2_100)
        #expect(snapshot.targets.caloriesKcal == 0)
        #expect(snapshot.targets.proteinGrams == 0)
    }

    @Test("weekly trend persists across snapshots")
    func trendPersistence() async throws {
        let store = try PersistenceStore.inMemory()
        try store.trainingPlan.save(.default)
        try saveDefaultBodyProfile(in: store)

        let endDay = HelmDay(year: 2026, month: 7, day: 23)
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

        let engine = NutritionEngine(persistence: store)
        let first = await engine.snapshot(for: endDay, prescriptionSummary: nil)
        let second = await engine.snapshot(for: endDay, prescriptionSummary: nil)

        #expect(first.trend.weeklyIntakeAverageKcal != nil)
        #expect(second.trend.estimatedTDEEKcal != nil)
        #expect(second.trend.weeklyIntakeAverageKcal == first.trend.weeklyIntakeAverageKcal)
    }

    @Test("post-workout tiny active burn stays stale")
    func postWorkoutTinyBurnStale() async throws {
        let store = try PersistenceStore.inMemory()
        try store.trainingPlan.save(.default)

        let calendar = Calendar(identifier: .gregorian)
        let dob = calendar.date(byAdding: .year, value: -30, to: Date())!
        try BodyProfileStore(metadata: store.appMetadata).save(
            BodyProfile(
                bodyMassKg: 80,
                heightCm: 175,
                biologicalSex: .male,
                dateOfBirth: dob
            )
        )

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let day = HelmDay.day(for: now, calendar: calendar)
        try store.dailyMetrics.upsert(
            DailyMetrics(
                helmDay: day,
                activeEnergy: Energy(kilocalories: 35)
            )
        )

        let workoutEnded = now.addingTimeInterval(-20 * 60)
        try store.workoutSessions.insert(
            WorkoutSessionDraft(
                id: "session-1",
                title: "Push",
                startedAt: workoutEnded.addingTimeInterval(-3_600),
                endedAt: workoutEnded,
                status: .completed,
                source: .manual,
                exercises: []
            )
        )

        let engine = NutritionEngine(persistence: store, calendar: calendar)
        let snapshot = await engine.snapshot(for: day, prescriptionSummary: nil, now: now)

        #expect(snapshot.activeEnergyFreshness == .stale(partialKilocalories: 35))
        #expect(snapshot.energyBalance.adjustedTargetKcal == nil)
    }

    @Test("active burn remains context without adjusting calorie target")
    func activeBurnDoesNotAdjustTarget() {
        let balance = EnergyBalanceSummary.build(
            intakeKcal: 1_800,
            baseTargetKcal: 2_400,
            activeEnergy: .fresh(kilocalories: 420)
        )
        #expect(balance.adjustedTargetKcal == nil)
        #expect(balance.activeEnergy == .fresh(kilocalories: 420))

        let staleBalance = EnergyBalanceSummary.build(
            intakeKcal: 1_800,
            baseTargetKcal: 2_400,
            activeEnergy: .stale(partialKilocalories: 42)
        )
        #expect(staleBalance.adjustedTargetKcal == nil)
    }

    @Test("today training day without active energy is stale pending")
    func trainingDayPending() {
        let freshness = ActiveEnergyFreshnessResolver.resolve(
            ActiveEnergyFreshnessResolver.Context(
                helmDay: HelmDay(year: 2026, month: 7, day: 31),
                activeEnergyKcal: nil,
                dayType: .training,
                isToday: true,
                latestWorkoutEndedAt: nil,
                now: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )

        #expect(freshness == .stale(partialKilocalories: nil))
    }

    @Test("past day with active energy is always fresh")
    func pastDayFresh() {
        let freshness = ActiveEnergyFreshnessResolver.resolve(
            ActiveEnergyFreshnessResolver.Context(
                helmDay: HelmDay(year: 2026, month: 7, day: 20),
                activeEnergyKcal: 512,
                dayType: .rest,
                isToday: false,
                latestWorkoutEndedAt: nil,
                now: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )

        #expect(freshness == .fresh(kilocalories: 512))
    }

    @Test("today rest day without active energy is unavailable")
    func restDayUnavailable() {
        let freshness = ActiveEnergyFreshnessResolver.resolve(
            ActiveEnergyFreshnessResolver.Context(
                helmDay: HelmDay(year: 2026, month: 7, day: 31),
                activeEnergyKcal: nil,
                dayType: .rest,
                isToday: true,
                latestWorkoutEndedAt: nil,
                now: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )

        #expect(freshness == .unavailable)
    }

    @Test("snapshot calorie target matches weekly-budget eat-to")
    func snapshotUsesWeeklyBudgetEatTo() async throws {
        let store = try PersistenceStore.inMemory()
        try store.trainingPlan.save(.default)
        try saveDefaultBodyProfile(in: store)

        let day = HelmDay(year: 2026, month: 8, day: 25)
        let engine = NutritionEngine(persistence: store)
        let snapshot = await engine.snapshot(for: day, prescriptionSummary: nil)

        let budgetDay = try #require(snapshot.budgetDay)
        #expect(snapshot.targets.caloriesKcal == budgetDay.eatToCaloriesKcal)
        #expect(snapshot.targets.proteinGrams == budgetDay.proteinGrams)
        #expect(snapshot.targets.carbohydrateGrams == budgetDay.carbohydrateGrams)
        #expect(snapshot.targets.fatGrams == budgetDay.fatGrams)
        #expect(snapshot.eatToKcal == budgetDay.eatToCaloriesKcal)
        #expect(snapshot.plannedKcal == budgetDay.plannedCaloriesKcal)
    }

    @Test("in-progress logging does not collapse today's eat-to")
    func inProgressLogDoesNotCollapseEatTo() async throws {
        let store = try PersistenceStore.inMemory()
        try store.trainingPlan.save(.default)
        try saveDefaultBodyProfile(in: store)

        let day = HelmDay(year: 2026, month: 8, day: 25)
        try store.nutrition.upsertDay(
            NutritionDay(
                helmDay: day,
                totalEnergy: Energy(kilocalories: 600),
                totalProteinGrams: 40,
                totalCarbohydrateGrams: 50,
                totalFatGrams: 20
            )
        )

        let engine = NutritionEngine(persistence: store)
        let snapshot = await engine.snapshot(for: day, prescriptionSummary: nil)
        let budgetDay = try #require(snapshot.budgetDay)

        #expect(snapshot.loggedKcal == 600)
        #expect(budgetDay.state == .remaining)
        #expect(budgetDay.consumedCaloriesKcal == nil)
        #expect(snapshot.eatToKcal > 1_200)
        #expect(snapshot.eatToKcal != 600)
        #expect(snapshot.remainingKcal == snapshot.eatToKcal - 600)
    }
}
