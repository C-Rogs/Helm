import Core
import Diagnostics
import Foundation
import NutritionKit
import OSLog
import Persistence

public enum FoodResolutionConfidence: String, Sendable, Equatable, Codable {
    case exact
    case synonym
    case partial
    case branded
    case custom
    case fallback
}

public enum FoodResolutionSource: String, Sendable, Equatable {
    case recent
    case productCache
    case cofid
    case openFoodFacts
    case custom
}

public struct ResolvedFoodProduct: Sendable, Equatable {
    public let ref: FoodProductRef
    public let per100gKcal: Double
    public let per100gProteinG: Double
    public let per100gCarbsG: Double
    public let per100gFatG: Double
    public let confidence: FoodResolutionConfidence
    public let suggestedGrams: Double?
    public let servingLabel: String?
    public let source: FoodResolutionSource

    public init(
        ref: FoodProductRef,
        per100gKcal: Double,
        per100gProteinG: Double,
        per100gCarbsG: Double,
        per100gFatG: Double,
        confidence: FoodResolutionConfidence,
        suggestedGrams: Double? = nil,
        servingLabel: String? = nil,
        source: FoodResolutionSource
    ) {
        self.ref = ref
        self.per100gKcal = per100gKcal
        self.per100gProteinG = per100gProteinG
        self.per100gCarbsG = per100gCarbsG
        self.per100gFatG = per100gFatG
        self.confidence = confidence
        self.suggestedGrams = suggestedGrams
        self.servingLabel = servingLabel
        self.source = source
    }
}

public struct FoodSearchResult: Sendable, Equatable {
    public let product: ResolvedFoodProduct
}

public enum FoodResolverError: Error, Sendable, Equatable {
    case offline
    case notFound
}

public actor FoodResolver {
    private let foodLog: FoodLogRepository
    private let cofidLookup: NutritionLookup
    private let offClient: any OpenFoodFactsClient
    private let networkGate: any NetworkGating
    private let now: @Sendable () -> Date
    private let log: Logger

    public init(
        persistence: PersistenceStore,
        cofidLookup: NutritionLookup = NutritionLookup(),
        offClient: any OpenFoodFactsClient = LiveOpenFoodFactsClient(),
        networkGate: any NetworkGating = LiveNetworkGate(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        foodLog = persistence.foodLog
        self.cofidLookup = cofidLookup
        self.offClient = offClient
        self.networkGate = networkGate
        self.now = now
        log = helmLogger(category: .healthKitIngest)
    }

    init(
        foodLog: FoodLogRepository,
        cofidLookup: NutritionLookup,
        offClient: any OpenFoodFactsClient,
        networkGate: any NetworkGating,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.foodLog = foodLog
        self.cofidLookup = cofidLookup
        self.offClient = offClient
        self.networkGate = networkGate
        self.now = now
        log = helmLogger(category: .healthKitIngest)
    }

    public func search(query: String, limit: Int = 20) async throws -> [FoodSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var results: [FoodSearchResult] = []
        var seen = Set<String>()

        for recent in try foodLog.fetchRecents(limit: 50) where matches(query: trimmed, displayName: recent.ref.displayName) {
            guard seen.insert(recent.ref.cacheKey).inserted else { continue }
            results.append(FoodSearchResult(product: resolved(from: recent)))
            if results.count >= limit { return results }
        }

        for name in cofidLookup.suggestionNames(matching: trimmed, limit: limit) {
            guard let cofidMatch = cofidLookup.resolve(item: name) else { continue }
            let ref = FoodProductRef(origin: .cofid, externalID: cofidMatch.record.fdcId, displayName: cofidMatch.record.description)
            guard seen.insert(ref.cacheKey).inserted else { continue }
            results.append(FoodSearchResult(product: resolved(from: cofidMatch, ref: ref)))
            if results.count >= limit { return results }
        }

        guard await networkGate.isOnline() else {
            return results
        }

        do {
            let offProducts = try await offClient.search(query: trimmed, pageSize: limit)
            for offProduct in offProducts {
                let resolved = try cacheAndResolve(offProduct: offProduct)
                guard seen.insert(resolved.ref.cacheKey).inserted else { continue }
                results.append(FoodSearchResult(product: resolved))
                if results.count >= limit { return results }
            }
        } catch {
            log.debug("OFF search skipped after local hits: \(String(describing: type(of: error)), privacy: .public)")
            Task {
                await DiagnosticsLog.shared.capture(
                    error: error,
                    category: .healthKitIngest,
                    message: "OFF search failed",
                    context: ["queryLength": String(trimmed.count)]
                )
            }
        }

        return results
    }

    public func resolveBarcode(_ barcode: String) async throws -> ResolvedFoodProduct {
        let trimmed = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FoodResolverError.notFound
        }

        let ref = FoodProductRef(origin: .openFoodFacts, externalID: trimmed, displayName: trimmed)
        if let cached = try foodLog.fetchCacheEntry(ref: ref) {
            log.debug("Barcode resolved from product cache barcode=\(trimmed, privacy: .public)")
            return resolved(from: cached, source: .productCache)
        }

        guard await networkGate.isOnline() else {
            throw FoodResolverError.offline
        }

        let offProduct = try await offClient.fetchProduct(barcode: trimmed)
        return try cacheAndResolve(offProduct: offProduct)
    }

    public func resolve(query: String) async throws -> ResolvedFoodProduct? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let recent = try foodLog.fetchRecents(limit: 50).first(where: { matches(query: trimmed, displayName: $0.ref.displayName) }) {
            return resolved(from: recent)
        }

        if let cofid = cofidLookup.resolve(item: trimmed) {
            let ref = FoodProductRef(origin: .cofid, externalID: cofid.record.fdcId, displayName: cofid.record.description)
            return resolved(from: cofid, ref: ref)
        }

        guard await networkGate.isOnline() else {
            return nil
        }

        let offProducts = try await offClient.search(query: trimmed, pageSize: 1)
        guard let offProduct = offProducts.first else {
            return nil
        }
        return try cacheAndResolve(offProduct: offProduct)
    }

    public func resolveCustom(
        ref: FoodProductRef,
        per100gKcal: Double,
        per100gProteinG: Double,
        per100gCarbsG: Double,
        per100gFatG: Double,
        suggestedGrams: Double? = nil,
        servingLabel: String? = nil
    ) throws -> ResolvedFoodProduct {
        let entry = FoodProductCacheEntry(
            ref: ref,
            per100gKcal: per100gKcal,
            per100gProteinG: per100gProteinG,
            per100gCarbsG: per100gCarbsG,
            per100gFatG: per100gFatG,
            updatedAt: now()
        )
        try foodLog.upsertCacheEntry(entry)
        return ResolvedFoodProduct(
            ref: ref,
            per100gKcal: per100gKcal,
            per100gProteinG: per100gProteinG,
            per100gCarbsG: per100gCarbsG,
            per100gFatG: per100gFatG,
            confidence: .custom,
            suggestedGrams: suggestedGrams,
            servingLabel: servingLabel,
            source: .custom
        )
    }

    private func cacheAndResolve(offProduct: OpenFoodFactsProduct) throws -> ResolvedFoodProduct {
        let ref = FoodProductRef(
            origin: .openFoodFacts,
            externalID: offProduct.barcode,
            displayName: offProduct.displayName
        )
        let entry = FoodProductCacheEntry(
            ref: ref,
            per100gKcal: offProduct.per100gKcal,
            per100gProteinG: offProduct.per100gProteinG,
            per100gCarbsG: offProduct.per100gCarbsG,
            per100gFatG: offProduct.per100gFatG,
            snapshotJSON: offProduct.rawJSON,
            updatedAt: now()
        )
        try foodLog.upsertCacheEntry(entry)
        return ResolvedFoodProduct(
            ref: ref,
            per100gKcal: offProduct.per100gKcal,
            per100gProteinG: offProduct.per100gProteinG,
            per100gCarbsG: offProduct.per100gCarbsG,
            per100gFatG: offProduct.per100gFatG,
            confidence: .branded,
            source: .openFoodFacts
        )
    }

    private func resolved(from recent: FoodLogRecent) -> ResolvedFoodProduct {
        if let cached = try? foodLog.fetchCacheEntry(ref: recent.ref) {
            return ResolvedFoodProduct(
                ref: recent.ref,
                per100gKcal: cached.per100gKcal,
                per100gProteinG: cached.per100gProteinG,
                per100gCarbsG: cached.per100gCarbsG,
                per100gFatG: cached.per100gFatG,
                confidence: recent.ref.origin == .openFoodFacts ? .branded : .exact,
                suggestedGrams: recent.grams,
                servingLabel: recent.servingLabel,
                source: .recent
            )
        }

        if recent.ref.origin == .cofid, let cofid = cofidLookup.resolve(item: recent.ref.displayName) {
            return ResolvedFoodProduct(
                ref: recent.ref,
                per100gKcal: cofid.record.per100g.kcal,
                per100gProteinG: cofid.record.per100g.proteinG,
                per100gCarbsG: cofid.record.per100g.carbsG,
                per100gFatG: cofid.record.per100g.fatG,
                confidence: confidence(for: cofid.matchConfidence),
                suggestedGrams: recent.grams,
                servingLabel: recent.servingLabel,
                source: .recent
            )
        }

        return ResolvedFoodProduct(
            ref: recent.ref,
            per100gKcal: 0,
            per100gProteinG: 0,
            per100gCarbsG: 0,
            per100gFatG: 0,
            confidence: .fallback,
            suggestedGrams: recent.grams,
            servingLabel: recent.servingLabel,
            source: .recent
        )
    }

    private func resolved(from cofid: ResolvedNutrition, ref: FoodProductRef) -> ResolvedFoodProduct {
        ResolvedFoodProduct(
            ref: ref,
            per100gKcal: cofid.record.per100g.kcal,
            per100gProteinG: cofid.record.per100g.proteinG,
            per100gCarbsG: cofid.record.per100g.carbsG,
            per100gFatG: cofid.record.per100g.fatG,
            confidence: confidence(for: cofid.matchConfidence),
            source: .cofid
        )
    }

    private func resolved(from cache: FoodProductCacheEntry, source: FoodResolutionSource) -> ResolvedFoodProduct {
        ResolvedFoodProduct(
            ref: cache.ref,
            per100gKcal: cache.per100gKcal,
            per100gProteinG: cache.per100gProteinG,
            per100gCarbsG: cache.per100gCarbsG,
            per100gFatG: cache.per100gFatG,
            confidence: cache.ref.origin == .openFoodFacts ? .branded : .custom,
            source: source
        )
    }

    private func confidence(for match: ResolvedNutrition.MatchConfidence) -> FoodResolutionConfidence {
        switch match {
        case .exact:
            .exact
        case .synonym:
            .synonym
        case .partial:
            .partial
        case .fallback:
            .fallback
        }
    }

    private func matches(query: String, displayName: String) -> Bool {
        let normalizedQuery = NutritionLookup.normalize(query)
        let normalizedName = NutritionLookup.normalize(displayName)
        guard !normalizedQuery.isEmpty else { return false }
        return normalizedName.contains(normalizedQuery) || normalizedQuery.contains(normalizedName)
    }
}
