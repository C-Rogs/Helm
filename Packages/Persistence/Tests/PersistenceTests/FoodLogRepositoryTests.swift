import Core
import Foundation
import Testing
@testable import Persistence

@Suite("Food log persistence")
struct FoodLogRepositoryTests {
    private let day = HelmDay(year: 2026, month: 7, day: 24)
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    private var loggedAt: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 24, hour: 8, minute: 15))!
    }

    private var foodRef: FoodProductRef {
        FoodProductRef(origin: .cofid, externalID: "13-145", displayName: "Porridge oats, raw")
    }

    private var brandedRef: FoodProductRef {
        FoodProductRef(origin: .openFoodFacts, externalID: "5050159001234", displayName: "Grenade Carb Killa")
    }

    @Test("meal with bucket round trips")
    func mealBucketRoundTrip() throws {
        let store = try PersistenceStore.inMemory()
        let meal = MealRecord(
            helmDay: day,
            name: "Work breakfast",
            loggedAt: loggedAt,
            bucket: .breakfast,
            energy: Energy(kilocalories: 520),
            proteinGrams: 28,
            carbohydrateGrams: 62,
            fatGrams: 16,
            source: .manual
        )

        try store.nutrition.upsertMeal(meal)
        let fetched = try store.nutrition.fetchMeal(id: meal.id)

        #expect(fetched == meal)
    }

    @Test("meal line items round trip")
    func mealLineItemsRoundTrip() throws {
        let store = try PersistenceStore.inMemory()
        let mealID = UUID()
        let meal = MealRecord(
            id: mealID,
            helmDay: day,
            name: "Oats + whey",
            loggedAt: loggedAt,
            bucket: .breakfast,
            energy: Energy(kilocalories: 520),
            proteinGrams: 28,
            carbohydrateGrams: 62,
            fatGrams: 16,
            source: .manual
        )
        let lineItems = [
            MealLineItemRecord(
                mealID: mealID,
                foodRef: foodRef,
                grams: 60,
                servingLabel: "dry scoop",
                energyKcal: 230,
                proteinG: 8,
                carbsG: 40,
                fatG: 4,
                sortOrder: 0
            ),
            MealLineItemRecord(
                mealID: mealID,
                foodRef: FoodProductRef(origin: .custom, externalID: "whey-1", displayName: "Whey isolate"),
                grams: 30,
                energyKcal: 110,
                proteinG: 24,
                carbsG: 2,
                fatG: 1,
                sortOrder: 1
            )
        ]

        try store.nutrition.upsertMeal(meal)
        try store.foodLog.replaceLineItems(for: mealID, with: lineItems)
        let fetched = try store.foodLog.fetchLineItems(for: mealID)

        #expect(fetched == lineItems)
    }

    @Test("deleting meal cascades line items")
    func deleteMealCascadesLineItems() throws {
        let store = try PersistenceStore.inMemory()
        let mealID = UUID()
        let meal = MealRecord(
            id: mealID,
            helmDay: day,
            name: "Snack",
            loggedAt: loggedAt,
            bucket: .snacks,
            energy: Energy(kilocalories: 180),
            source: .quickAdd
        )
        let lineItem = MealLineItemRecord(
            mealID: mealID,
            foodRef: brandedRef,
            grams: 60,
            energyKcal: 180,
            proteinG: 20,
            carbsG: 8,
            fatG: 6,
            sortOrder: 0
        )

        try store.nutrition.upsertMeal(meal)
        try store.foodLog.upsertLineItems([lineItem])
        try store.nutrition.deleteMeal(id: mealID)

        #expect(try store.foodLog.fetchLineItems(for: mealID).isEmpty)
    }

    @Test("meal template round trip")
    func mealTemplateRoundTrip() throws {
        let store = try PersistenceStore.inMemory()
        let template = MealTemplate(
            name: "Work breakfast",
            bucket: .breakfast,
            lineItems: [
                MealLineItem(
                    name: "Porridge oats, raw",
                    grams: 60,
                    caloriesKcal: 230,
                    proteinG: 8,
                    carbsG: 40,
                    fatG: 4,
                    usdaMatchID: "13-145",
                    matchConfidence: .high
                ),
                MealLineItem(
                    name: "Whey isolate",
                    grams: 30,
                    caloriesKcal: 110,
                    proteinG: 24,
                    carbsG: 2,
                    fatG: 1,
                    matchConfidence: .medium
                )
            ],
            updatedAt: loggedAt
        )

        try store.mealTemplates.save(template)
        let fetched = try store.mealTemplates.fetch(id: template.id)

        #expect(fetched == template)
    }

    @Test("product cache and portion preference round trip")
    func cacheAndPortionRoundTrip() throws {
        let store = try PersistenceStore.inMemory()
        let cacheEntry = FoodProductCacheEntry(
            ref: brandedRef,
            per100gKcal: 380,
            per100gProteinG: 35,
            per100gCarbsG: 18,
            per100gFatG: 12,
            snapshotJSON: #"{"code":"5050159001234"}"#,
            updatedAt: loggedAt
        )
        let preference = FoodPortionPreference(
            foodRef: brandedRef,
            grams: 60,
            servingLabel: "1 bar",
            lastUsedAt: loggedAt
        )
        let recent = FoodLogRecent(
            ref: foodRef,
            grams: 60,
            servingLabel: "dry scoop",
            lastUsedAt: loggedAt
        )

        try store.foodLog.upsertCacheEntry(cacheEntry)
        try store.foodLog.upsertPortionPreference(preference)
        try store.foodLog.upsertRecent(recent)

        #expect(try store.foodLog.fetchCacheEntry(ref: brandedRef) == cacheEntry)
        #expect(try store.foodLog.fetchPortionPreference(ref: brandedRef) == preference)
        #expect(try store.foodLog.fetchRecents(limit: 10) == [recent])
    }

    @Test("pending food import round trip")
    func pendingImportRoundTrip() throws {
        let store = try PersistenceStore.inMemory()
        let pending = PendingFoodImport(
            createdAt: loggedAt,
            barcode: "5050159001234",
            provisionalLineItems: [
                MealLineItem(
                    name: "Unknown bar",
                    grams: 60,
                    caloriesKcal: 0,
                    proteinG: 0,
                    carbsG: 0,
                    fatG: 0,
                    matchConfidence: .low
                )
            ],
            status: .pending
        )

        try store.foodLog.insertPendingImport(pending)
        let fetched = try store.foodLog.fetchPendingImports(status: .pending)

        #expect(fetched == [pending])

        var resolved = pending
        resolved = PendingFoodImport(
            id: pending.id,
            createdAt: pending.createdAt,
            barcode: pending.barcode,
            photoMealID: pending.photoMealID,
            provisionalLineItems: pending.provisionalLineItems,
            status: .resolved
        )
        try store.foodLog.updatePendingImport(resolved)

        #expect(try store.foodLog.fetchPendingImports(status: .pending).isEmpty)
        #expect(try store.foodLog.fetchPendingImports(status: .resolved) == [resolved])
    }
}
