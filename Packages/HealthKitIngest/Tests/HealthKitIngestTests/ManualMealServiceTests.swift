import Core
import Foundation
import NutritionKit
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("Manual meal service")
struct ManualMealServiceTests {
    private let loggedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private var grenadeProduct: ResolvedFoodProduct {
        ResolvedFoodProduct(
            ref: FoodProductRef(
                origin: .openFoodFacts,
                externalID: "5050159001234",
                displayName: "Grenade Carb Killa"
            ),
            per100gKcal: 380,
            per100gProteinG: 35,
            per100gCarbsG: 18,
            per100gFatG: 12,
            confidence: .branded,
            suggestedGrams: 60,
            servingLabel: "1 bar",
            source: .openFoodFacts
        )
    }

    @Test("fixture food logs to GRDB and fake HK writer")
    func logFoodPersistsLocally() async throws {
        let store = try PersistenceStore.inMemory()
        let service = ManualMealService(
            writer: MealHealthKitWriter(store: MockHealthKitStoreClient()),
            localStore: ManualMealLocalStore(store: store)
        )

        let saved = try await service.logFood(
            product: grenadeProduct,
            grams: 60,
            servingLabel: "1 bar",
            bucket: .snacks,
            loggedAt: loggedAt,
            mealID: "manual-food-meal"
        )

        #expect(saved.mealID == "manual-food-meal")
        #expect(
            MealHealthKitWriter.shouldReIngest(
                savedMeal: saved,
                ownBundleID: HealthKitIngest.defaultOwnBundleID
            ) == false
        )

        let helmDay = HelmDay.day(for: loggedAt)
        let meals = try store.nutrition.fetchMeals(for: helmDay)
        #expect(meals.count == 1)
        #expect(meals[0].source == .manual)
        #expect(meals[0].bucket == .snacks)
        #expect(meals[0].energy?.kilocalories == 228)

        let lineItems = try store.foodLog.fetchLineItems(for: meals[0].id)
        #expect(lineItems.count == 1)
        #expect(lineItems[0].foodRef.displayName == "Grenade Carb Killa")
        #expect(lineItems[0].grams == 60)

        let nutritionDay = try store.nutrition.fetchDay(helmDay: helmDay)
        #expect(nutritionDay?.totalEnergy?.kilocalories == 228)
    }

    @Test("quick-add kcal-only counts toward TDEE trend")
    func quickAddFeedsTDEE() async throws {
        let store = try PersistenceStore.inMemory()
        try store.trainingPlan.save(.default)
        let calendar = Calendar(identifier: .gregorian)
        let dob = try #require(calendar.date(byAdding: .year, value: -30, to: Date()))
        try BodyProfileStore(metadata: store.appMetadata).save(
            BodyProfile(bodyMassKg: 80, heightCm: 175, biologicalSex: .male, dateOfBirth: dob)
        )

        let endDay = HelmDay.day(for: loggedAt)
        for offset in 0 ..< 6 {
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
                BodyComposition(helmDay: day, mass: Mass(kilograms: 80), measuredAt: loggedAt)
            )
        }

        let service = ManualMealService(
            writer: MealHealthKitWriter(store: MockHealthKitStoreClient()),
            localStore: ManualMealLocalStore(store: store)
        )
        _ = try await service.logQuickAdd(
            kilocalories: 740,
            label: "Beer",
            bucket: .dinner,
            loggedAt: loggedAt,
            mealID: "quick-add-meal"
        )

        let engine = NutritionEngine(persistence: store)
        let snapshot = await engine.snapshot(for: endDay, prescriptionSummary: nil)

        #expect(snapshot.actual?.totalEnergy?.kilocalories == 740)
        #expect(snapshot.actual?.macroGapKilocalories == 740)
        #expect(snapshot.trend.weeklyIntakeAverageKcal != nil)
        let weekInputs = try NutritionTrendBuilder.weekInputs(from: store, endingAt: endDay)
        #expect(weekInputs.first { $0.helmDay == endDay }?.loggedIntakeKcal == 740)
    }

    @Test("explicit alcohol entry does not inflate macro gap")
    func alcoholReducesMacroGap() async throws {
        let store = try PersistenceStore.inMemory()
        let service = ManualMealService(
            writer: MealHealthKitWriter(store: MockHealthKitStoreClient()),
            localStore: ManualMealLocalStore(store: store)
        )

        _ = try await service.logAlcohol(
            preset: .beer,
            quantity: 2,
            bucket: .dinner,
            loggedAt: loggedAt,
            mealID: "alcohol-meal"
        )

        let helmDay = HelmDay.day(for: loggedAt)
        let nutritionDay = try store.nutrition.fetchDay(helmDay: helmDay)
        #expect(nutritionDay?.totalEnergy?.kilocalories == 420)
        #expect(nutritionDay?.macroGapKilocalories == nil)

        let meals = try store.nutrition.fetchMeals(for: helmDay)
        #expect(meals.count == 1)
        #expect(meals[0].source == .alcohol)
    }

    @Test("own HK writes are not re-ingested")
    func dedupOwnWrites() async throws {
        let store = try PersistenceStore.inMemory()
        let service = ManualMealService(
            writer: MealHealthKitWriter(store: MockHealthKitStoreClient()),
            localStore: ManualMealLocalStore(store: store)
        )

        let saved = try await service.logQuickAdd(
            kilocalories: 500,
            label: "Snack",
            bucket: .snacks,
            loggedAt: loggedAt,
            mealID: "dedup-meal"
        )

        #expect(
            MealHealthKitWriter.shouldReIngest(
                savedMeal: saved,
                ownBundleID: HealthKitIngest.defaultOwnBundleID
            ) == false
        )
        #expect(
            IngestSampleFilter.shouldIngest(
                sourceBundleID: saved.energy.sourceBundleID,
                ownBundleID: HealthKitIngest.defaultOwnBundleID
            ) == false
        )
    }

    @Test("GRDB meal sums preferred over stale HK metrics")
    func resolverPrefersMealSums() async throws {
        let store = try PersistenceStore.inMemory()
        let helmDay = HelmDay.day(for: loggedAt)

        try store.dailyMetrics.upsert(
            DailyMetrics(
                helmDay: helmDay,
                dietaryEnergy: Energy(kilocalories: 3_000),
                dietaryProteinGrams: 200,
                dietaryCarbohydrateGrams: 300,
                dietaryFatGrams: 90
            )
        )

        let service = ManualMealService(
            writer: MealHealthKitWriter(store: MockHealthKitStoreClient()),
            localStore: ManualMealLocalStore(store: store)
        )
        _ = try await service.logQuickAdd(
            kilocalories: 740,
            bucket: .snacks,
            loggedAt: loggedAt
        )

        let meals = try store.nutrition.fetchMeals(for: helmDay)
        let actual = NutritionActualResolver.resolve(
            helmDay: helmDay,
            storedDay: try store.nutrition.fetchDay(helmDay: helmDay),
            dailyMetrics: try store.dailyMetrics.fetch(helmDay: helmDay),
            meals: meals
        )

        #expect(actual?.totalEnergy?.kilocalories == 740)
        #expect(actual?.totalEnergy?.kilocalories != 3_000)
    }
}
