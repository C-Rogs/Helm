import Core
import Foundation
import NutritionKit
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("Meal repeat service")
struct MealRepeatServiceTests {
    private let loggedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private var today: HelmDay { HelmDay.day(for: loggedAt) }
    private var yesterday: HelmDay { today.adding(days: -1) }

    private var yogurtRef: FoodProductRef {
        FoodProductRef(origin: .openFoodFacts, externalID: "5000112611234", displayName: "Arla Protein Yogurt")
    }

    private func makeService(store: PersistenceStore) -> MealRepeatService {
        MealRepeatService(
            store: store,
            manualMealService: ManualMealService(
                writer: MealHealthKitWriter(store: MockHealthKitStoreClient()),
                localStore: ManualMealLocalStore(store: store)
            ),
            now: { loggedAt }
        )
    }

    @Test("portion memory defaults to last serving on second log")
    func portionMemoryDefaultsToLastServing() async throws {
        let store = try PersistenceStore.inMemory()
        let service = ManualMealService(
            writer: MealHealthKitWriter(store: MockHealthKitStoreClient()),
            localStore: ManualMealLocalStore(store: store, now: { loggedAt })
        )
        let product = ResolvedFoodProduct(
            ref: yogurtRef,
            per100gKcal: 78,
            per100gProteinG: 10,
            per100gCarbsG: 6,
            per100gFatG: 0.2,
            confidence: .branded,
            source: .openFoodFacts
        )

        _ = try await service.logFood(
            product: product,
            grams: 200,
            servingLabel: "1 pot",
            bucket: .breakfast,
            loggedAt: loggedAt
        )

        _ = try await service.logFood(
            product: product,
            grams: 200,
            servingLabel: "1 pot",
            bucket: .breakfast,
            loggedAt: loggedAt.addingTimeInterval(60)
        )

        let preference = try store.foodLog.fetchPortionPreference(ref: yogurtRef)
        #expect(preference?.grams == 200)
        #expect(preference?.servingLabel == "1 pot")

        let defaults = FoodPortionDefaultsResolver.defaults(for: product, storedPreference: preference)
        #expect(defaults.grams == 200)
        #expect(defaults.servingLabel == "1 pot")
        #expect(defaults.prefersServingLabel)
    }

    @Test("template logs multi-item breakfast in one action")
    func templateLogsMultiItemBreakfast() async throws {
        let store = try PersistenceStore.inMemory()
        let repeatService = makeService(store: store)
        let template = MealTemplate(
            name: "Work breakfast",
            bucket: .breakfast,
            lineItems: (1 ... 7).map { index in
                MealLineItem(
                    name: "Item \(index)",
                    grams: Double(index * 10),
                    caloriesKcal: Double(index * 20),
                    proteinG: Double(index),
                    carbsG: Double(index * 2),
                    fatG: Double(index),
                    usdaMatchID: "custom:\(index)",
                    matchConfidence: .high
                )
            },
            updatedAt: loggedAt
        )

        _ = try await repeatService.logTemplate(template)

        let meals = try store.nutrition.fetchMeals(for: today)
        #expect(meals.count == 1)
        #expect(meals[0].source == .template)
        #expect(meals[0].bucket == .breakfast)
        #expect(meals[0].name == "Work breakfast")

        let lineItems = try store.foodLog.fetchLineItems(for: meals[0].id)
        #expect(lineItems.count == 7)
        #expect(lineItems.map(\.energyKcal) == (1 ... 7).map { Double($0 * 20) })
    }

    @Test("copy bucket duplicates line items to target day")
    func copyBucketDuplicatesLineItems() async throws {
        let store = try PersistenceStore.inMemory()
        let repeatService = makeService(store: store)
        let calendar = Calendar(identifier: .gregorian)
        let sourceLoggedAt = yesterday.startInstant(calendar: calendar)!.addingTimeInterval(3_600)
        let sourceMealID = UUID()
        let sourceMeal = MealRecord(
            id: sourceMealID,
            helmDay: yesterday,
            name: "Tuesday breakfast",
            loggedAt: sourceLoggedAt,
            bucket: .breakfast,
            energy: Energy(kilocalories: 420),
            proteinGrams: 28,
            carbohydrateGrams: 52,
            fatGrams: 10,
            source: .manual
        )
        let lineItems = [
            MealLineItemRecord(
                mealID: sourceMealID,
                foodRef: FoodProductRef(origin: .cofid, externalID: "13-145", displayName: "Porridge oats, raw"),
                grams: 60,
                servingLabel: "dry scoop",
                energyKcal: 230,
                proteinG: 8,
                carbsG: 40,
                fatG: 4,
                sortOrder: 0
            ),
            MealLineItemRecord(
                mealID: sourceMealID,
                foodRef: FoodProductRef(origin: .custom, externalID: "whey-1", displayName: "Whey isolate"),
                grams: 30,
                energyKcal: 110,
                proteinG: 24,
                carbsG: 2,
                fatG: 1,
                sortOrder: 1
            )
        ]

        try store.nutrition.upsertMeal(sourceMeal)
        try store.foodLog.replaceLineItems(for: sourceMealID, with: lineItems)

        let copiedCount = try await repeatService.copyBucket(
            from: yesterday,
            bucket: .breakfast,
            to: today
        )

        #expect(copiedCount == 1)

        let todayMeals = try store.nutrition.fetchMeals(for: today)
        #expect(todayMeals.count == 1)
        #expect(todayMeals[0].bucket == .breakfast)
        #expect(todayMeals[0].name == "Tuesday breakfast")

        let copiedItems = try store.foodLog.fetchLineItems(for: todayMeals[0].id)
        #expect(copiedItems.count == 2)
        #expect(copiedItems.map(\.foodRef.displayName) == lineItems.map(\.foodRef.displayName))
        #expect(copiedItems.map(\.grams) == lineItems.map(\.grams))
        #expect(copiedItems.map(\.servingLabel) == lineItems.map(\.servingLabel))
    }

    @Test("copy all meals duplicates every bucket to target day")
    func copyAllMealsDuplicatesEveryBucket() async throws {
        let store = try PersistenceStore.inMemory()
        let repeatService = makeService(store: store)
        let calendar = Calendar(identifier: .gregorian)
        let sourceLoggedAt = yesterday.startInstant(calendar: calendar)!.addingTimeInterval(3_600)

        for (index, bucket) in [MealBucket.breakfast, .lunch, .dinner].enumerated() {
            let mealID = UUID()
            try store.nutrition.upsertMeal(
                MealRecord(
                    id: mealID,
                    helmDay: yesterday,
                    name: "\(bucket.displayName) meal",
                    loggedAt: sourceLoggedAt.addingTimeInterval(Double(index * 3_600)),
                    bucket: bucket,
                    energy: Energy(kilocalories: 300),
                    proteinGrams: 20,
                    carbohydrateGrams: 30,
                    fatGrams: 8,
                    source: .manual
                )
            )
            try store.foodLog.replaceLineItems(
                for: mealID,
                with: [
                    MealLineItemRecord(
                        mealID: mealID,
                        foodRef: FoodProductRef(origin: .custom, externalID: bucket.rawValue, displayName: bucket.displayName),
                        grams: 100,
                        energyKcal: 300,
                        proteinG: 20,
                        carbsG: 30,
                        fatG: 8,
                        sortOrder: 0
                    )
                ]
            )
        }

        let copiedCount = try await repeatService.copyAllMeals(from: yesterday, to: today)
        #expect(copiedCount == 3)

        let todayMeals = try store.nutrition.fetchMeals(for: today)
        #expect(todayMeals.count == 3)
        #expect(Set(todayMeals.map(\.bucket)) == Set([.breakfast, .lunch, .dinner]))
    }

    @Test("save template from bucket snapshots line items")
    func saveTemplateFromBucket() throws {
        let store = try PersistenceStore.inMemory()
        let repeatService = makeService(store: store)
        let mealID = UUID()
        try store.nutrition.upsertMeal(
            MealRecord(
                id: mealID,
                helmDay: today,
                name: "Oats",
                loggedAt: loggedAt,
                bucket: .breakfast,
                energy: Energy(kilocalories: 230),
                proteinGrams: 8,
                carbohydrateGrams: 40,
                fatGrams: 4,
                source: .manual
            )
        )
        try store.foodLog.replaceLineItems(
            for: mealID,
            with: [
                MealLineItemRecord(
                    mealID: mealID,
                    foodRef: FoodProductRef(origin: .cofid, externalID: "13-145", displayName: "Porridge oats, raw"),
                    grams: 60,
                    servingLabel: "dry scoop",
                    energyKcal: 230,
                    proteinG: 8,
                    carbsG: 40,
                    fatG: 4,
                    sortOrder: 0
                )
            ]
        )

        let template = try repeatService.buildTemplate(name: "Weekday oats", bucket: .breakfast, helmDay: today)
        #expect(template?.lineItems.count == 1)
        #expect(template?.lineItems[0].usdaMatchID == "cofid:13-145")
        try repeatService.saveTemplate(try #require(template))

        let fetched = try store.mealTemplates.fetchAll()
        #expect(fetched.count == 1)
        #expect(fetched[0].name == "Weekday oats")
    }
}
