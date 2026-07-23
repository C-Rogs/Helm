import Core
import Foundation
import NutritionKit
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("Nutrition service")
struct NutritionServiceTests {
    @Test("fixture intake renders targets vs actual with alcohol gap")
    func targetsVsActualWithGap() async throws {
        let store = try PersistenceStore.inMemory()
        try store.trainingPlan.save(.default)

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
        let snapshot = try await engine.snapshot(for: day, prescriptionSummary: nil)

        #expect(snapshot.actual?.helmDay == alcoholDay.helmDay)
        #expect(snapshot.actual?.macroGapKilocalories != nil)
        #expect(snapshot.targets.macroGapKilocalories! > 100)
        #expect(snapshot.targets.carbohydrateGrams > 0)
        #expect(snapshot.dayType == .rest)
    }

    @Test("weekly trend persists across snapshots")
    func trendPersistence() async throws {
        let store = try PersistenceStore.inMemory()
        try store.trainingPlan.save(.default)

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
        let first = try await engine.snapshot(for: endDay, prescriptionSummary: nil)
        let second = try await engine.snapshot(for: endDay, prescriptionSummary: nil)

        #expect(first.trend.weeklyIntakeAverageKcal != nil)
        #expect(second.trend.estimatedTDEEKcal != nil)
        #expect(second.trend.weeklyIntakeAverageKcal == first.trend.weeklyIntakeAverageKcal)
    }
}
