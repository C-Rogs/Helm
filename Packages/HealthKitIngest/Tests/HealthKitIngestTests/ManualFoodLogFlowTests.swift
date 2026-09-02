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

    @Test("produce defaults to medium portion when available")
    func produceDefaultsToMediumPortion() {
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

        #expect(defaults.grams == 118)
        #expect(defaults.servingLabel == "1 medium")
        #expect(defaults.prefersServingLabel == true)
        if case .weight = defaults.inputMode {
            #expect(Bool(true))
        } else {
            Issue.record("Banana should stay in weight input mode")
        }
    }

    @Test("barcode products still show the portion step")
    func neverSkipsPortionStep() {
        let product = ResolvedFoodProduct(
            ref: grenadeRef,
            per100gKcal: 380,
            per100gProteinG: 35,
            per100gCarbsG: 18,
            per100gFatG: 12,
            confidence: .branded,
            suggestedGrams: 60,
            servingLabel: "1 bar",
            source: .openFoodFacts
        )
        #expect(!FoodPortionDefaultsResolver.shouldSkipPortionStep(for: product))
    }

    @Test("apple defaults to one whole countable unit")
    func appleDefaultsToWhole() {
        let product = ResolvedFoodProduct(
            ref: FoodProductRef(
                origin: .cofid,
                externalID: "14-018",
                displayName: "Apple, eating"
            ),
            per100gKcal: 47,
            per100gProteinG: 0.4,
            per100gCarbsG: 11.8,
            per100gFatG: 0.1,
            confidence: .exact,
            source: .cofid
        )
        let defaults = FoodPortionDefaultsResolver.defaults(for: product, storedPreference: nil)
        #expect(defaults.servingLabel == "1 whole")
        if case .countable(let config) = defaults.inputMode {
            #expect(config.unitNoun == "whole")
        } else {
            Issue.record("Apple should use countable whole")
        }
    }

    @Test("egg pack avoids whole-pack default grams")
    func eggPackUsesPerEggDefault() {
        let product = ResolvedFoodProduct(
            ref: FoodProductRef(
                origin: .openFoodFacts,
                externalID: "1234567890123",
                displayName: "Coop 6 large free range eggs"
            ),
            per100gKcal: 154,
            per100gProteinG: 12.5,
            per100gCarbsG: 0.5,
            per100gFatG: 11,
            confidence: .branded,
            suggestedGrams: 300,
            servingLabel: nil,
            source: .openFoodFacts
        )

        let defaults = FoodPortionDefaultsResolver.defaults(for: product, storedPreference: nil)

        #expect(defaults.grams == 50)
        #expect(defaults.defaultSizeLabel == "1 large")
        if case .countable = defaults.inputMode {
            #expect(Bool(true))
        } else {
            Issue.record("Egg pack should use countable input mode")
        }
    }

    @Test("barcode bar with gram serving defaults to one unit")
    func barGramServingIsOneUnit() {
        let product = ResolvedFoodProduct(
            ref: FoodProductRef(
                origin: .openFoodFacts,
                externalID: "5055040001234",
                displayName: "PhD Smart Protein Bar"
            ),
            per100gKcal: 380,
            per100gProteinG: 35,
            per100gCarbsG: 18,
            per100gFatG: 12,
            confidence: .branded,
            suggestedGrams: 35,
            servingLabel: "35 g",
            source: .openFoodFacts
        )

        let defaults = FoodPortionDefaultsResolver.defaults(for: product, storedPreference: nil)

        #expect(defaults.defaultQuantity == 1)
        #expect(defaults.grams == 35)
        #expect(defaults.servingLabel == "1 bar")
    }

    @Test("gram serving on packaged food is not a portion count")
    func packagedGramServingIsOneWhole() {
        let product = ResolvedFoodProduct(
            ref: grenadeRef,
            per100gKcal: 380,
            per100gProteinG: 35,
            per100gCarbsG: 18,
            per100gFatG: 12,
            confidence: .branded,
            suggestedGrams: 35,
            servingLabel: "35 g",
            source: .openFoodFacts
        )

        let defaults = FoodPortionDefaultsResolver.defaults(for: product, storedPreference: nil)

        #expect(defaults.defaultQuantity == 1)
        #expect(defaults.grams == 35)
        #expect(defaults.servingLabel == "1 whole")
    }
}

@Suite("Manual food log flow")
struct ManualFoodLogFlowTests {
    private let loggedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let calendar = Calendar(identifier: .gregorian)

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

        let helmDay = HelmDay.day(for: loggedAt, calendar: calendar)
        let meals = try store.nutrition.fetchMeals(for: helmDay)
        #expect(meals.count == 1)
        #expect(meals[0].source == .barcode)
        #expect(meals[0].name.contains("Grenade"))
    }

    @Test("quick-add dinner on today diary day appears in fetch and dinner bucket")
    func quickAddDinnerOnTodayDiaryDay() async throws {
        let store = try PersistenceStore.inMemory()
        let service = makeManualMealService(store: store)
        let calendar = Calendar(identifier: .gregorian)
        let todayHelmDay = HelmDay(year: 2023, month: 11, day: 15)
        let loggedAt = try #require(
            calendar.date(from: DateComponents(year: 2023, month: 11, day: 15, hour: 12))
        )

        try await logQuickAddLikeController(
            service: service,
            kilocalories: 700,
            bucket: .dinner,
            loggingHelmDay: todayHelmDay,
            todayHelmDay: todayHelmDay,
            loggedAt: loggedAt
        )

        try assertDinnerQuickAddVisible(in: store, helmDay: todayHelmDay)
    }

    @Test("quick-add dinner on past diary day appears in fetch and dinner bucket")
    func quickAddDinnerOnPastDiaryDay() async throws {
        let store = try PersistenceStore.inMemory()
        let service = makeManualMealService(store: store)
        let calendar = Calendar(identifier: .gregorian)
        let todayHelmDay = HelmDay(year: 2023, month: 11, day: 15)
        let pastHelmDay = HelmDay(year: 2023, month: 11, day: 14)
        let loggedAt = MealLogInstant.loggedAt(
            for: pastHelmDay,
            bucket: .dinner,
            today: todayHelmDay,
            calendar: calendar
        )

        try await logQuickAddLikeController(
            service: service,
            kilocalories: 700,
            bucket: .dinner,
            loggingHelmDay: pastHelmDay,
            todayHelmDay: todayHelmDay,
            loggedAt: loggedAt
        )

        try assertDinnerQuickAddVisible(in: store, helmDay: pastHelmDay)

        let todayMeals = try store.nutrition.fetchMeals(for: todayHelmDay)
        #expect(todayMeals.isEmpty)
    }

    @Test("explicit helmDay keeps early-morning quick-add on selected diary day")
    func quickAddHonorsExplicitHelmDayBeforeCutoff() async throws {
        let store = try PersistenceStore.inMemory()
        let service = makeManualMealService(store: store)
        let calendar = Calendar(identifier: .gregorian)
        let selectedHelmDay = HelmDay(year: 2023, month: 11, day: 15)
        let loggedAt = try #require(
            calendar.date(from: DateComponents(year: 2023, month: 11, day: 15, hour: 3))
        )
        let derivedHelmDay = HelmDay.day(for: loggedAt, calendar: calendar)
        #expect(derivedHelmDay == HelmDay(year: 2023, month: 11, day: 14))

        try await logQuickAddLikeController(
            service: service,
            kilocalories: 700,
            bucket: .dinner,
            loggingHelmDay: selectedHelmDay,
            todayHelmDay: selectedHelmDay,
            loggedAt: loggedAt
        )

        try assertDinnerQuickAddVisible(in: store, helmDay: selectedHelmDay)
        #expect(try store.nutrition.fetchMeals(for: derivedHelmDay).isEmpty)
    }
}

private extension ManualFoodLogFlowTests {
    func makeManualMealService(store: PersistenceStore) -> ManualMealService {
        ManualMealService(
            writer: MealHealthKitWriter(store: MockHealthKitStoreClient()),
            localStore: ManualMealLocalStore(store: store, calendar: calendar)
        )
    }

    func logQuickAddLikeController(
        service: ManualMealService,
        kilocalories: Double,
        bucket: MealBucket,
        loggingHelmDay: HelmDay,
        todayHelmDay: HelmDay,
        loggedAt: Date
    ) async throws {
        let controllerLoggedAt = MealLogInstant.loggedAt(
            for: loggingHelmDay,
            bucket: bucket,
            today: todayHelmDay,
            calendar: calendar,
            now: loggedAt
        )
        _ = try await service.logQuickAdd(
            kilocalories: kilocalories,
            label: "Quick dinner",
            bucket: bucket,
            loggedAt: controllerLoggedAt,
            helmDay: loggingHelmDay
        )
    }

    func assertDinnerQuickAddVisible(
        in store: PersistenceStore,
        helmDay: HelmDay
    ) throws {
        let meals = try store.nutrition.fetchMeals(for: helmDay)
        #expect(meals.count == 1)
        #expect(meals[0].helmDay == helmDay)
        #expect(meals[0].bucket == .dinner)
        #expect(meals[0].source == .quickAdd)
        #expect(meals[0].energy?.kilocalories == 700)

        let buckets = try NutritionMealBucketProjection.mealsByBucket(for: helmDay, store: store)
        #expect(buckets[.dinner]?.count == 1)
        #expect(buckets[.dinner]?.first?.id == meals[0].id)
        #expect(buckets[.breakfast]?.isEmpty == true)
        #expect(buckets[.lunch]?.isEmpty == true)
        #expect(buckets[.snacks]?.isEmpty == true)
    }
}
