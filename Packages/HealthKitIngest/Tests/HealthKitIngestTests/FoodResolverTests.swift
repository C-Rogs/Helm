import Core
import Foundation
import NutritionKit
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("Food resolver")
struct FoodResolverTests {
    private let loggedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let grenadeRef = FoodProductRef(
        origin: .openFoodFacts,
        externalID: "5050159001234",
        displayName: "Grenade Carb Killa"
    )

    private func makeResolver(
        store: PersistenceStore,
        offClient: any OpenFoodFactsClient,
        online: Bool
    ) -> FoodResolver {
        FoodResolver(
            foodLog: store.foodLog,
            cofidLookup: NutritionLookup(),
            offClient: offClient,
            networkGate: FixedNetworkGate(online: online),
            now: { loggedAt }
        )
    }

    @Test("resolver chain prefers recents over CoFID and OFF")
    func recentsWinChain() async throws {
        let store = try PersistenceStore.inMemory()
        let offClient = FixtureOpenFoodFactsClient(bundle: .module)
        let recent = FoodLogRecent(
            ref: grenadeRef,
            grams: 60,
            servingLabel: "1 bar",
            lastUsedAt: loggedAt
        )
        try store.foodLog.upsertRecent(recent)
        try store.foodLog.upsertCacheEntry(
            FoodProductCacheEntry(
                ref: grenadeRef,
                per100gKcal: 380,
                per100gProteinG: 35,
                per100gCarbsG: 18,
                per100gFatG: 12,
                updatedAt: loggedAt
            )
        )

        let resolver = makeResolver(store: store, offClient: offClient, online: true)
        let results = try await resolver.searchLocal(query: "Grenade", limit: 5)

        #expect(results.first?.product.source == .recent)
        #expect(results.first?.product.suggestedGrams == 60)
        #expect(offClient.requestCount == 0)
    }

    @Test("CoFID resolves generic foods without network")
    func cofidOfflineSearch() async throws {
        let store = try PersistenceStore.inMemory()
        let offClient = FixtureOpenFoodFactsClient(bundle: .module)
        let resolver = makeResolver(store: store, offClient: offClient, online: false)

        let results = try await resolver.searchLocal(query: "banana", limit: 5)

        #expect(!results.isEmpty)
        #expect(results.contains { $0.product.source == .cofid })
        #expect(offClient.requestCount == 0)
    }

    @Test("OFF search runs when online and caches product")
    func offSearchCachesProduct() async throws {
        let store = try PersistenceStore.inMemory()
        let offClient = FixtureOpenFoodFactsClient(bundle: .module)
        let resolver = makeResolver(store: store, offClient: offClient, online: true)

        let results = try await resolver.searchRemote(query: "Grenade Carb Killa", limit: 5)

        #expect(results.contains { $0.product.ref == grenadeRef })
        #expect(results.contains { $0.product.source == .openFoodFacts })
        #expect(offClient.requestCount == 1)

        let cached = try store.foodLog.fetchCacheEntry(ref: grenadeRef)
        #expect(cached?.per100gKcal == 380)
        #expect(cached?.snapshotJSON?.contains("5050159001234") == true)
    }

    @Test("barcode cache hit skips OFF network")
    func barcodeCacheSkipsNetwork() async throws {
        let store = try PersistenceStore.inMemory()
        let offClient = FixtureOpenFoodFactsClient(bundle: .module)
        try store.foodLog.upsertCacheEntry(
            FoodProductCacheEntry(
                ref: grenadeRef,
                per100gKcal: 380,
                per100gProteinG: 35,
                per100gCarbsG: 18,
                per100gFatG: 12,
                snapshotJSON: #"{"code":"5050159001234"}"#,
                updatedAt: loggedAt
            )
        )

        let resolver = makeResolver(store: store, offClient: offClient, online: true)
        let resolved = try await resolver.resolveBarcode("5050159001234")

        #expect(resolved.source == .productCache)
        #expect(resolved.per100gKcal == 380)
        #expect(offClient.requestCount == 0)
    }

    @Test("barcode lookup is offline without cache")
    func barcodeOfflineThrows() async throws {
        let store = try PersistenceStore.inMemory()
        let offClient = FixtureOpenFoodFactsClient(bundle: .module)
        let resolver = makeResolver(store: store, offClient: offClient, online: false)

        await #expect(throws: FoodResolverError.offline) {
            try await resolver.resolveBarcode("5050159001234")
        }
        #expect(offClient.requestCount == 0)
    }

    @Test("barcode lookup fetches OFF and writes cache when online")
    func barcodeFetchesAndCaches() async throws {
        let store = try PersistenceStore.inMemory()
        let offClient = FixtureOpenFoodFactsClient(bundle: .module)
        let resolver = makeResolver(store: store, offClient: offClient, online: true)

        let resolved = try await resolver.resolveBarcode("5050159001234")

        #expect(resolved.source == .openFoodFacts)
        #expect(resolved.ref.externalID == "5050159001234")
        #expect(offClient.requestCount == 1)
        #expect(try store.foodLog.fetchCacheEntry(ref: grenadeRef) != nil)
    }

    @Test("local search never calls OFF")
    func localSearchSkipsOFF() async throws {
        let store = try PersistenceStore.inMemory()
        let offClient = FixtureOpenFoodFactsClient(bundle: .module)
        let resolver = makeResolver(store: store, offClient: offClient, online: true)

        _ = try await resolver.searchLocal(query: "Grenade Carb Killa", limit: 5)

        #expect(offClient.requestCount == 0)
    }

    @Test("cached branded products match partial token queries locally")
    func cachedProductTokenSearch() async throws {
        let store = try PersistenceStore.inMemory()
        let offClient = FixtureOpenFoodFactsClient(bundle: .module)
        let getProRef = FoodProductRef(
            origin: .openFoodFacts,
            externalID: "3033490085558",
            displayName: "Danone GetPro blueberry yogurt"
        )
        try store.foodLog.upsertCacheEntry(
            FoodProductCacheEntry(
                ref: getProRef,
                per100gKcal: 74,
                per100gProteinG: 7.5,
                per100gCarbsG: 4.2,
                per100gFatG: 0.8,
                updatedAt: loggedAt
            )
        )

        let resolver = makeResolver(store: store, offClient: offClient, online: true)
        let results = try await resolver.searchLocal(query: "getpro yogurt", limit: 5)

        #expect(results.contains { $0.product.ref == getProRef })
        #expect(results.first?.product.source == .productCache)
        #expect(offClient.requestCount == 0)
    }

    @Test("recents match partial token queries locally")
    func recentTokenSearch() async throws {
        let store = try PersistenceStore.inMemory()
        let offClient = FixtureOpenFoodFactsClient(bundle: .module)
        let getProRef = FoodProductRef(
            origin: .openFoodFacts,
            externalID: "3033490085558",
            displayName: "Danone GetPro blueberry yogurt"
        )
        try store.foodLog.upsertRecent(
            FoodLogRecent(
                ref: getProRef,
                grams: 160,
                servingLabel: "1 pot",
                lastUsedAt: loggedAt
            )
        )
        try store.foodLog.upsertCacheEntry(
            FoodProductCacheEntry(
                ref: getProRef,
                per100gKcal: 74,
                per100gProteinG: 7.5,
                per100gCarbsG: 4.2,
                per100gFatG: 0.8,
                updatedAt: loggedAt
            )
        )

        let resolver = makeResolver(store: store, offClient: offClient, online: true)
        let results = try await resolver.searchLocal(query: "getpro yogurt", limit: 5)

        #expect(results.first?.product.source == .recent)
        #expect(offClient.requestCount == 0)
    }

    @Test("remote search requires at least three characters")
    func remoteSearchMinLength() async throws {
        let store = try PersistenceStore.inMemory()
        let offClient = FixtureOpenFoodFactsClient(bundle: .module)
        let resolver = makeResolver(store: store, offClient: offClient, online: true)

        await #expect(throws: FoodResolverError.queryTooShort) {
            try await resolver.searchRemote(query: "ab", limit: 5)
        }
        #expect(offClient.requestCount == 0)
    }

    @Test("custom food writes product cache")
    func customFoodCaches() async throws {
        let store = try PersistenceStore.inMemory()
        let offClient = FixtureOpenFoodFactsClient(bundle: .module)
        let resolver = makeResolver(store: store, offClient: offClient, online: true)
        let customRef = FoodProductRef(origin: .custom, externalID: "whey-1", displayName: "Whey isolate")

        let resolved = try await resolver.resolveCustom(
            ref: customRef,
            per100gKcal: 400,
            per100gProteinG: 80,
            per100gCarbsG: 8,
            per100gFatG: 6,
            suggestedGrams: 30,
            servingLabel: "1 scoop"
        )

        #expect(resolved.source == .custom)
        #expect(resolved.confidence == .custom)
        #expect(try store.foodLog.fetchCacheEntry(ref: customRef)?.per100gProteinG == 80)
    }

    @Test("gin and tonic remote search reaches OFF when CoFID is empty")
    func ginAndTonicReachesOFF() async throws {
        let store = try PersistenceStore.inMemory()
        let offClient = FixtureOpenFoodFactsClient(bundle: .module)
        let resolver = makeResolver(store: store, offClient: offClient, online: true)

        let local = try await resolver.searchLocal(query: "gin and tonic", limit: 20)
        #expect(local.isEmpty)

        _ = try await resolver.searchRemote(query: "gin and tonic", limit: 20)
        #expect(offClient.requestCount == 1)
    }

    @Test("resolve(query) skips CoFID fallback and reaches OFF")
    func resolveQuerySkipsFallbackReachesOFF() async throws {
        let store = try PersistenceStore.inMemory()
        let offClient = FixtureOpenFoodFactsClient(bundle: .module)
        let resolver = makeResolver(store: store, offClient: offClient, online: true)

        let resolved = try await resolver.resolve(query: "gin and tonic")
        #expect(resolved?.source == .openFoodFacts || resolved == nil)
        #expect(offClient.requestCount >= 1)
        #expect(resolved?.confidence != .fallback)
    }

    @Test("cached ginger tonic does not match gin tonic query")
    func ginDoesNotMatchGinger() async throws {
        let store = try PersistenceStore.inMemory()
        let offClient = FixtureOpenFoodFactsClient(bundle: .module)
        let gingerRef = FoodProductRef(
            origin: .openFoodFacts,
            externalID: "ginger-tonic-1",
            displayName: "Ginger tonic"
        )
        try store.foodLog.upsertCacheEntry(
            FoodProductCacheEntry(
                ref: gingerRef,
                per100gKcal: 40,
                per100gProteinG: 0,
                per100gCarbsG: 10,
                per100gFatG: 0,
                updatedAt: loggedAt
            )
        )

        let resolver = makeResolver(store: store, offClient: offClient, online: true)
        let results = try await resolver.searchLocal(query: "gin tonic", limit: 10)
        #expect(!results.contains { $0.product.ref == gingerRef })
    }
}

@Suite("Open Food Facts client")
struct OpenFoodFactsClientTests {
    @Test("fixture barcode parses Grenade product")
    func fixtureBarcode() async throws {
        let client = FixtureOpenFoodFactsClient(bundle: .module)
        let product = try await client.fetchProduct(barcode: "5050159001234")

        #expect(product.barcode == "5050159001234")
        #expect(product.displayName.contains("Grenade"))
        #expect(product.per100gKcal == 380)
        #expect(product.per100gProteinG == 35)
    }

    @Test("fixture search returns branded hits")
    func fixtureSearch() async throws {
        let client = FixtureOpenFoodFactsClient(bundle: .module)
        let products = try await client.search(query: "grenade bar", pageSize: 5)

        #expect(products.count == 1)
        #expect(products[0].barcode == "5050159001234")
    }

    @Test("Search-a-licious fixture parses brands array and display name")
    func searchALiciousBrandsArray() async throws {
        let client = FixtureOpenFoodFactsClient(bundle: .module)
        let products = try await client.search(query: "getpro yogurt", pageSize: 5)

        #expect(products.count == 1)
        #expect(products[0].barcode == "5060360507477")
        #expect(products[0].brand == "Danone")
        #expect(products[0].displayName == "Danone GetPRO Blueberry Flavour")
        #expect(products[0].per100gKcal == 53.1)
    }

    @Test("Search-a-licious response parser accepts hits payload")
    func parseSearchALiciousFixture() throws {
        let url = try #require(Bundle.module.url(forResource: "off_search_grenade", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let products = try OpenFoodFactsParser.parseSearchALiciousResponse(data: data)

        #expect(products.count == 1)
        #expect(products[0].brand == "Grenade")
        #expect(products[0].rawJSON.contains("5050159001234"))
    }

    @Test("missing barcode fixture throws not found")
    func missingBarcode() async {
        let client = FixtureOpenFoodFactsClient(bundle: .module)
        await #expect(throws: OpenFoodFactsError.productNotFound) {
            try await client.fetchProduct(barcode: "9999999999999")
        }
    }

    @Test("mislabeled kJ in energy-kcal field converts to kcal")
    func mislabeledEnergyField() async throws {
        let client = FixtureOpenFoodFactsClient(bundle: .module)
        let product = try await client.fetchProduct(barcode: "3033490085558")

        #expect(product.displayName.contains("GetPro"))
        #expect(abs(product.per100gKcal - 73.6) < 1)
    }
}
