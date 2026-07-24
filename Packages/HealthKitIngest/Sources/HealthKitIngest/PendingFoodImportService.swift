import Core
import Diagnostics
import Foundation
import OSLog
import Persistence

public struct PendingImportResolveSummary: Sendable, Equatable {
    public let resolvedCount: Int
    public let failedCount: Int

    public init(resolvedCount: Int, failedCount: Int) {
        self.resolvedCount = resolvedCount
        self.failedCount = failedCount
    }
}

public enum PendingFoodImportError: Error, Sendable, Equatable {
    case mealNotFound
    case missingBarcode
}

/// Queues offline branded lookups and resolves them when network returns.
public actor PendingFoodImportService {
    private let foodLog: FoodLogRepository
    private let foodResolver: FoodResolver
    private let manualMealService: ManualMealService
    private let localStore: ManualMealLocalStore
    private let networkGate: any NetworkGating
    private let now: @Sendable () -> Date
    private let onResolved: @Sendable (Int) async -> Void
    private let log: Logger

    public init(
        persistence: PersistenceStore,
        foodResolver: FoodResolver,
        manualMealService: ManualMealService,
        networkGate: any NetworkGating = LiveNetworkGate(),
        now: @escaping @Sendable () -> Date = Date.init,
        onResolved: @escaping @Sendable (Int) async -> Void = { _ in }
    ) {
        foodLog = persistence.foodLog
        self.foodResolver = foodResolver
        self.manualMealService = manualMealService
        localStore = ManualMealLocalStore(store: persistence)
        self.networkGate = networkGate
        self.now = now
        self.onResolved = onResolved
        log = helmLogger(category: .healthKitIngest)
    }

    init(
        foodLog: FoodLogRepository,
        foodResolver: FoodResolver,
        manualMealService: ManualMealService,
        localStore: ManualMealLocalStore,
        networkGate: any NetworkGating,
        now: @escaping @Sendable () -> Date = Date.init,
        onResolved: @escaping @Sendable (Int) async -> Void = { _ in }
    ) {
        self.foodLog = foodLog
        self.foodResolver = foodResolver
        self.manualMealService = manualMealService
        self.localStore = localStore
        self.networkGate = networkGate
        self.now = now
        self.onResolved = onResolved
        log = helmLogger(category: .healthKitIngest)
    }

    public func queueOfflineBarcode(
        barcode: String,
        bucket: MealBucket,
        grams: Double = FoodPortionDefaultsResolver.produceDefaultGrams,
        servingLabel: String? = nil,
        loggedAt: Date? = nil
    ) async throws -> UUID {
        let trimmed = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FoodResolverError.notFound
        }

        let loggedAt = loggedAt ?? now()
        let mealID = UUID()
        let placeholderRef = FoodProductRef(
            origin: .openFoodFacts,
            externalID: trimmed,
            displayName: "Barcode \(trimmed)"
        )
        let provisionalLineItem = MealLineItem(
            name: placeholderRef.displayName,
            grams: grams,
            caloriesKcal: 0,
            proteinG: 0,
            carbsG: 0,
            fatG: 0,
            matchConfidence: .low
        )
        let pendingImport = PendingFoodImport(
            createdAt: loggedAt,
            barcode: trimmed,
            photoMealID: mealID,
            provisionalLineItems: [provisionalLineItem],
            status: .pending
        )

        let record = MealLineItemRecord(
            mealID: mealID,
            foodRef: placeholderRef,
            grams: grams,
            servingLabel: servingLabel,
            energyKcal: 0,
            proteinG: 0,
            carbsG: 0,
            fatG: 0,
            sortOrder: 0
        )

        _ = try await manualMealService.logCompositeMeal(
            name: "Pending \(trimmed)",
            bucket: bucket,
            lineItems: [record],
            loggedAt: loggedAt,
            mealID: mealID.uuidString.lowercased(),
            source: .barcode
        )
        try foodLog.insertPendingImport(pendingImport)
        log.debug("Queued offline barcode import barcode=\(trimmed, privacy: .public) mealID=\(mealID.uuidString, privacy: .public)")
        return mealID
    }

    @discardableResult
    public func resolvePendingImports() async -> PendingImportResolveSummary {
        guard await networkGate.isOnline() else {
            return PendingImportResolveSummary(resolvedCount: 0, failedCount: 0)
        }

        let pending = (try? foodLog.fetchPendingImports(status: .pending)) ?? []
        guard !pending.isEmpty else {
            return PendingImportResolveSummary(resolvedCount: 0, failedCount: 0)
        }

        var resolvedCount = 0
        var failedCount = 0

        for item in pending {
            do {
                try await resolve(item)
                resolvedCount += 1
            } catch FoodResolverError.notFound {
                try? markFailed(item)
                failedCount += 1
            } catch {
                log.debug("Pending import resolve failed id=\(item.id.uuidString, privacy: .public)")
                failedCount += 1
            }
        }

        if resolvedCount > 0 {
            await onResolved(resolvedCount)
        }

        return PendingImportResolveSummary(resolvedCount: resolvedCount, failedCount: failedCount)
    }

    private func resolve(_ item: PendingFoodImport) async throws {
        guard let barcode = item.barcode?.trimmingCharacters(in: .whitespacesAndNewlines), !barcode.isEmpty else {
            throw PendingFoodImportError.missingBarcode
        }
        guard let mealID = item.photoMealID else {
            throw PendingFoodImportError.mealNotFound
        }

        let product = try await foodResolver.resolveBarcode(barcode)
        let existingItems = try foodLog.fetchLineItems(for: mealID)
        guard let first = existingItems.first else {
            throw PendingFoodImportError.mealNotFound
        }
        guard let meal = try localStore.fetchMeal(id: mealID) else {
            throw PendingFoodImportError.mealNotFound
        }

        let grams = first.grams
        let macros = product.macros(forGrams: grams)
        let updatedLineItem = MealLineItemRecord(
            id: first.id,
            mealID: mealID,
            foodRef: product.ref,
            grams: grams,
            servingLabel: first.servingLabel,
            energyKcal: macros.energyKcal,
            proteinG: macros.proteinG,
            carbsG: macros.carbsG,
            fatG: macros.fatG,
            sortOrder: 0
        )

        _ = try await manualMealService.updateMeal(
            mealID: mealID,
            name: product.ref.displayName,
            bucket: meal.bucket,
            loggedAt: meal.loggedAt,
            macros: macros,
            lineItems: [updatedLineItem],
            source: .barcode
        )

        try foodLog.updatePendingImport(
            PendingFoodImport(
                id: item.id,
                createdAt: item.createdAt,
                barcode: item.barcode,
                photoMealID: item.photoMealID,
                provisionalLineItems: item.provisionalLineItems,
                status: .resolved
            )
        )
        log.debug("Resolved offline barcode import barcode=\(barcode, privacy: .public) mealID=\(mealID.uuidString, privacy: .public)")
    }

    private func markFailed(_ item: PendingFoodImport) throws {
        try foodLog.updatePendingImport(
            PendingFoodImport(
                id: item.id,
                createdAt: item.createdAt,
                barcode: item.barcode,
                photoMealID: item.photoMealID,
                provisionalLineItems: item.provisionalLineItems,
                status: .failed
            )
        )
    }
}
