import Core
import Foundation
import NutritionKit
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("Manual meal service")
struct ManualMealServiceTests {
    private let loggedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let calendar = Calendar(identifier: .gregorian)

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
        let mockHK = MockHealthKitStoreClient()
        let service = ManualMealService(
            writer: MealHealthKitWriter(store: mockHK),
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

        let helmDay = HelmDay.day(for: loggedAt, calendar: calendar)
        let meals = try store.nutrition.fetchMeals(for: helmDay)
        #expect(meals.count == 1)
        #expect(meals[0].source == .manual)
        #expect(meals[0].bucket == .snacks)
        #expect(meals[0].energy?.kilocalories == 228)

        await service.flushHealthKitWrites()
        #expect(mockHK.savedMealIDs.contains("manual-food-meal"))
        #expect(
            IngestSampleFilter.shouldIngest(
                sourceBundleID: HealthKitIngest.defaultOwnBundleID,
                ownBundleID: HealthKitIngest.defaultOwnBundleID
            ) == false
        )

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

        let endDay = HelmDay.day(for: loggedAt, calendar: calendar)
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

        let helmDay = HelmDay.day(for: loggedAt, calendar: calendar)
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
        let mockHK = MockHealthKitStoreClient()
        let service = ManualMealService(
            writer: MealHealthKitWriter(store: mockHK),
            localStore: ManualMealLocalStore(store: store)
        )

        _ = try await service.logQuickAdd(
            kilocalories: 500,
            label: "Snack",
            bucket: .snacks,
            loggedAt: loggedAt,
            mealID: "dedup-meal"
        )
        await service.flushHealthKitWrites()

        #expect(mockHK.savedMealIDs.contains("dedup-meal"))
        #expect(
            IngestSampleFilter.shouldIngest(
                sourceBundleID: HealthKitIngest.defaultOwnBundleID,
                ownBundleID: HealthKitIngest.defaultOwnBundleID
            ) == false
        )
    }

    @Test("GRDB meal sums preferred over stale HK metrics")
    func resolverPrefersMealSums() async throws {
        let store = try PersistenceStore.inMemory()
        let helmDay = HelmDay.day(for: loggedAt, calendar: calendar)

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

    @Test("edit meal updates totals and rewrites HK")
    func editMealUpdatesTotals() async throws {
        let store = try PersistenceStore.inMemory()
        let mockHK = MockHealthKitStoreClient()
        let service = ManualMealService(
            writer: MealHealthKitWriter(store: mockHK),
            localStore: ManualMealLocalStore(store: store)
        )

        let mealID = UUID()
        _ = try await service.logFood(
            product: grenadeProduct,
            grams: 60,
            bucket: .snacks,
            loggedAt: loggedAt,
            mealID: mealID.uuidString
        )

        _ = try await service.updateMeal(
            mealID: mealID,
            name: "Grenade bar (edited)",
            bucket: .snacks,
            loggedAt: loggedAt,
            macros: FoodPortionMacros(energyKcal: 300, proteinG: 40, carbsG: 10, fatG: 8),
            lineItems: [
                MealLineItemRecord(
                    mealID: mealID,
                    foodRef: grenadeProduct.ref,
                    grams: 80,
                    servingLabel: "1 bar",
                    energyKcal: 300,
                    proteinG: 40,
                    carbsG: 10,
                    fatG: 8,
                    sortOrder: 0
                )
            ],
            source: .manual
        )

        let helmDay = HelmDay.day(for: loggedAt, calendar: calendar)
        let nutritionDay = try store.nutrition.fetchDay(helmDay: helmDay)
        #expect(nutritionDay?.totalEnergy?.kilocalories == 300)

        let meals = try store.nutrition.fetchMeals(for: helmDay)
        #expect(meals[0].name == "Grenade bar (edited)")
        #expect(mockHK.deletedMealIDs.contains(mealID.uuidString.lowercased()))
        #expect(mockHK.savedMealIDs.contains(mealID.uuidString.lowercased()))
    }

    @Test("delete meal removes GRDB row and HK samples")
    func deleteMealRemovesAll() async throws {
        let store = try PersistenceStore.inMemory()
        let mockHK = MockHealthKitStoreClient()
        let service = ManualMealService(
            writer: MealHealthKitWriter(store: mockHK),
            localStore: ManualMealLocalStore(store: store)
        )

        let mealID = UUID()
        _ = try await service.logQuickAdd(
            kilocalories: 450,
            label: "Snack",
            bucket: .snacks,
            loggedAt: loggedAt,
            mealID: mealID.uuidString
        )

        try await service.deleteMeal(mealID: mealID)

        let helmDay = HelmDay.day(for: loggedAt, calendar: calendar)
        #expect(try store.nutrition.fetchMeals(for: helmDay).isEmpty)
        #expect(try store.nutrition.fetchDay(helmDay: helmDay) == nil)
        #expect(mockHK.deletedMealIDs == [mealID.uuidString.lowercased()])
    }

    @Test("log returns after GRDB before delayed HealthKit write")
    func logReturnsBeforeHealthKit() async throws {
        let store = try PersistenceStore.inMemory()
        let mockHK = MockHealthKitStoreClient()
        mockHK.mealSaveDelayNanoseconds = 200_000_000
        let service = ManualMealService(
            writer: MealHealthKitWriter(store: mockHK),
            localStore: ManualMealLocalStore(store: store)
        )

        _ = try await service.logQuickAdd(
            kilocalories: 450,
            label: "Snack",
            bucket: .snacks,
            loggedAt: loggedAt,
            mealID: "delayed-meal"
        )

        let helmDay = HelmDay.day(for: loggedAt, calendar: calendar)
        #expect(try store.nutrition.fetchMeals(for: helmDay).count == 1)
        #expect(mockHK.savedMealIDs.isEmpty)

        await service.flushHealthKitWrites()
        #expect(mockHK.savedMealIDs.contains("delayed-meal"))
    }

    @Test("HealthKit failure still keeps the GRDB meal")
    func healthKitFailureKeepsLocalMeal() async throws {
        let store = try PersistenceStore.inMemory()
        let mockHK = MockHealthKitStoreClient()
        mockHK.mealSaveShouldFail = true
        let service = ManualMealService(
            writer: MealHealthKitWriter(store: mockHK),
            localStore: ManualMealLocalStore(store: store)
        )

        _ = try await service.logQuickAdd(
            kilocalories: 450,
            bucket: .snacks,
            loggedAt: loggedAt,
            mealID: "local-only-meal"
        )
        await service.flushHealthKitWrites()

        let helmDay = HelmDay.day(for: loggedAt, calendar: calendar)
        #expect(try store.nutrition.fetchMeals(for: helmDay).count == 1)
        #expect(mockHK.savedMealIDs.isEmpty)
    }

    @Test("edit waits for in-flight HealthKit save before rewrite")
    func editWaitsForInFlightHealthKitSave() async throws {
        let store = try PersistenceStore.inMemory()
        let mockHK = MockHealthKitStoreClient()
        mockHK.mealSaveDelayNanoseconds = 150_000_000
        let service = ManualMealService(
            writer: MealHealthKitWriter(store: mockHK),
            localStore: ManualMealLocalStore(store: store)
        )

        let mealID = UUID()
        _ = try await service.logFood(
            product: grenadeProduct,
            grams: 60,
            bucket: .snacks,
            loggedAt: loggedAt,
            mealID: mealID.uuidString
        )

        _ = try await service.updateMeal(
            mealID: mealID,
            name: "Grenade bar (edited)",
            bucket: .snacks,
            loggedAt: loggedAt,
            macros: FoodPortionMacros(energyKcal: 300, proteinG: 40, carbsG: 10, fatG: 8),
            lineItems: [],
            source: .manual
        )

        let helmDay = HelmDay.day(for: loggedAt, calendar: calendar)
        #expect(try store.nutrition.fetchDay(helmDay: helmDay)?.totalEnergy?.kilocalories == 300)
        #expect(mockHK.deletedMealIDs.contains(mealID.uuidString.lowercased()))
        #expect(mockHK.savedMealIDs.contains(mealID.uuidString.lowercased()))
    }

    @Test("delete waits for in-flight HealthKit save so samples are not orphaned")
    func deleteWaitsForInFlightHealthKitSave() async throws {
        let store = try PersistenceStore.inMemory()
        let mockHK = MockHealthKitStoreClient()
        mockHK.mealSaveDelayNanoseconds = 150_000_000
        let service = ManualMealService(
            writer: MealHealthKitWriter(store: mockHK),
            localStore: ManualMealLocalStore(store: store)
        )

        let mealID = UUID()
        _ = try await service.logQuickAdd(
            kilocalories: 450,
            label: "Snack",
            bucket: .snacks,
            loggedAt: loggedAt,
            mealID: mealID.uuidString
        )

        try await service.deleteMeal(mealID: mealID)

        let helmDay = HelmDay.day(for: loggedAt, calendar: calendar)
        #expect(try store.nutrition.fetchMeals(for: helmDay).isEmpty)
        #expect(mockHK.savedMealIDs.isEmpty)
        #expect(mockHK.deletedMealIDs.contains(mealID.uuidString.lowercased()))
    }
}
