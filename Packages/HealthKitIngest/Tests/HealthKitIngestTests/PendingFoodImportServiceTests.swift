import Core
import Foundation
import NutritionKit
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("Pending food import service")
struct PendingFoodImportServiceTests {
    private let loggedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let barcode = "5050159001234"
    private let grenadeRef = FoodProductRef(
        origin: .openFoodFacts,
        externalID: "5050159001234",
        displayName: "Grenade Carb Killa"
    )

    private func makeService(
        store: PersistenceStore,
        online: Bool
    ) -> PendingFoodImportService {
        let offClient = FixtureOpenFoodFactsClient(bundle: .module)
        let foodResolver = FoodResolver(
            foodLog: store.foodLog,
            cofidLookup: NutritionLookup(),
            offClient: offClient,
            networkGate: FixedNetworkGate(online: online),
            now: { loggedAt }
        )
        let meals = ManualMealService(
            writer: MealHealthKitWriter(store: MockHealthKitStoreClient()),
            localStore: ManualMealLocalStore(store: store)
        )
        let executor = HelmActionExecutor(
            manualMealService: meals,
            persistence: store,
            mealRepeatService: MealRepeatService(store: store, manualMealService: meals)
        )
        return PendingFoodImportService(
            foodLog: store.foodLog,
            foodResolver: foodResolver,
            actionExecutor: executor,
            localStore: ManualMealLocalStore(store: store),
            networkGate: FixedNetworkGate(online: online),
            now: { loggedAt }
        )
    }

    @Test("offline barcode queue creates pending row and provisional meal")
    func offlineQueueCreatesPendingRow() async throws {
        let store = try PersistenceStore.inMemory()
        let service = makeService(store: store, online: false)

        let mealID = try await service.queueOfflineBarcode(
            barcode: barcode,
            bucket: .lunch,
            grams: 60,
            servingLabel: "1 bar"
        )

        let pending = try store.foodLog.fetchPendingImports(status: .pending)
        #expect(pending.count == 1)
        #expect(pending[0].barcode == barcode)
        #expect(pending[0].photoMealID == mealID)

        let meal = try store.nutrition.fetchMeal(id: mealID)
        #expect(meal?.name == "Pending \(barcode)")
        #expect(meal?.energy?.kilocalories == 0)

        let lineItems = try store.foodLog.fetchLineItems(for: mealID)
        #expect(lineItems.count == 1)
        #expect(lineItems[0].energyKcal == 0)
        #expect(lineItems[0].grams == 60)
    }

    @Test("reconnect resolves pending import to cached branded product")
    func reconnectResolvesPendingImport() async throws {
        let store = try PersistenceStore.inMemory()
        let offlineService = makeService(store: store, online: false)
        let mealID = try await offlineService.queueOfflineBarcode(
            barcode: barcode,
            bucket: .snacks,
            grams: 60
        )

        let onlineService = makeService(store: store, online: true)
        let summary = await onlineService.resolvePendingImports()

        #expect(summary.resolvedCount == 1)
        #expect(summary.failedCount == 0)
        #expect(try store.foodLog.fetchPendingImports(status: .pending).isEmpty)

        let resolvedImports = try store.foodLog.fetchPendingImports(status: .resolved)
        #expect(resolvedImports.count == 1)
        #expect(resolvedImports[0].photoMealID == mealID)

        let meal = try store.nutrition.fetchMeal(id: mealID)
        #expect(meal?.name.contains("Grenade") == true)
        #expect(meal?.energy?.kilocalories == 228)

        let lineItems = try store.foodLog.fetchLineItems(for: mealID)
        #expect(lineItems.count == 1)
        #expect(lineItems[0].foodRef == grenadeRef)
        #expect(lineItems[0].energyKcal == 228)

        let cached = try store.foodLog.fetchCacheEntry(ref: grenadeRef)
        #expect(cached?.per100gKcal == 380)
    }

    @Test("resolve skips work while offline")
    func resolveSkipsWhileOffline() async throws {
        let store = try PersistenceStore.inMemory()
        let service = makeService(store: store, online: false)
        _ = try await service.queueOfflineBarcode(barcode: barcode, bucket: .dinner)

        let summary = await service.resolvePendingImports()

        #expect(summary == PendingImportResolveSummary(resolvedCount: 0, failedCount: 0))
        #expect(try store.foodLog.fetchPendingImports(status: .pending).count == 1)
    }
}
