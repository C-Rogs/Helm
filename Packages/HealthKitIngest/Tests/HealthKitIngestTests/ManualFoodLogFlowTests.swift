import Core
import Foundation
import NutritionKit
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("Food portion defaults")
struct FoodPortionDefaultsTests {
    private let grenadeRef = FoodProductRef(
        origin: .openFoodFacts,
        externalID: "5050159001234",
        displayName: "Grenade Carb Killa"
    )

    private let bananaRef = FoodProductRef(
        origin: .cofid,
        externalID: "13-145",
        displayName: "Banana, flesh only"
    )

    @Test("packaged food prefers remembered serving")
    func packagedUsesStoredPreference() {
        let product = ResolvedFoodProduct(
            ref: grenadeRef,
            per100gKcal: 380,
            per100gProteinG: 35,
            per100gCarbsG: 18,
            per100gFatG: 12,
            confidence: .branded,
            source: .openFoodFacts
        )
        let preference = FoodPortionPreference(
            foodRef: grenadeRef,
            grams: 60,
            servingLabel: "1 bar",
            lastUsedAt: Date()
        )

        let defaults = FoodPortionDefaultsResolver.defaults(for: product, storedPreference: preference)

        #expect(defaults.grams == 60)
        #expect(defaults.servingLabel == "1 bar")
        #expect(defaults.prefersServingLabel)
    }

    @Test("produce defaults to grams")
    func produceDefaultsToGrams() {
        let product = ResolvedFoodProduct(
            ref: bananaRef,
            per100gKcal: 89,
            per100gProteinG: 1.1,
            per100gCarbsG: 20.3,
            per100gFatG: 0.3,
            confidence: .exact,
            source: .cofid
        )

        let defaults = FoodPortionDefaultsResolver.defaults(for: product, storedPreference: nil)

        #expect(defaults.grams == FoodPortionDefaultsResolver.produceDefaultGrams)
        #expect(defaults.servingLabel == nil)
        #expect(defaults.prefersServingLabel == false)
    }
}

@Suite("Manual food log flow")
struct ManualFoodLogFlowTests {
    private let loggedAt = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("search resolves fixture foods")
    func searchResolvesFixtureFoods() async throws {
        let store = try PersistenceStore.inMemory()
        let resolver = FoodResolver(
            foodLog: store.foodLog,
            cofidLookup: NutritionLookup(),
            offClient: FixtureOpenFoodFactsClient(bundle: .module),
            networkGate: FixedNetworkGate(online: true),
            now: { loggedAt }
        )

        let cofidResults = try await resolver.search(query: "banana", limit: 5)
        #expect(cofidResults.contains { $0.product.source == .cofid })

        let brandedResults = try await resolver.search(query: "Grenade Carb Killa", limit: 5)
        #expect(brandedResults.contains { $0.product.ref.externalID == "5050159001234" })
    }

    @Test("barcode fixture flow logs meal")
    func barcodeFixtureFlowLogsMeal() async throws {
        let store = try PersistenceStore.inMemory()
        let resolver = FoodResolver(
            foodLog: store.foodLog,
            cofidLookup: NutritionLookup(),
            offClient: FixtureOpenFoodFactsClient(bundle: .module),
            networkGate: FixedNetworkGate(online: true),
            now: { loggedAt }
        )
        let service = ManualMealService(
            writer: MealHealthKitWriter(store: MockHealthKitStoreClient()),
            localStore: ManualMealLocalStore(store: store)
        )

        let product = try await resolver.resolveBarcode("5050159001234")
        let defaults = FoodPortionDefaultsResolver.defaults(for: product, storedPreference: nil)

        let saved = try await service.logFood(
            product: product,
            grams: defaults.grams,
            servingLabel: defaults.servingLabel,
            bucket: .snacks,
            loggedAt: loggedAt,
            mealID: "barcode-flow-meal",
            source: .barcode
        )

        #expect(saved.mealID == "barcode-flow-meal")

        let helmDay = HelmDay.day(for: loggedAt)
        let meals = try store.nutrition.fetchMeals(for: helmDay)
        #expect(meals.count == 1)
        #expect(meals[0].source == .barcode)
        #expect(meals[0].name.contains("Grenade"))
    }
}
