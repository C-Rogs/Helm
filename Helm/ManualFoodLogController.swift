import Core
import DesignSystem
import HealthKitIngest
import Observation
import Persistence
import SwiftUI

enum AddFoodEntryMode: String, Identifiable {
    case search
    case barcode
    case quickAdd
    case alcohol

    var id: String { rawValue }
}

@MainActor
@Observable
final class ManualFoodLogController {
    enum Phase: Equatable {
        case idle
        case flow(AddFoodEntryMode)
        case saving
        case failed(String)
    }

    var phase: Phase = .idle
    var isOnline = true
    var preferredBucket: MealBucket = .snacks

    private let foodResolver: FoodResolver
    private let manualMealService: ManualMealService
    private let pendingImportService: PendingFoodImportService
    private let networkGate: any NetworkGating
    private let portionPreferenceLoader: @Sendable (FoodProductRef) throws -> FoodPortionPreference?
    private let onLogged: @MainActor () -> Void
    private var wasOnline = true

    init(
        foodResolver: FoodResolver,
        manualMealService: ManualMealService,
        pendingImportService: PendingFoodImportService,
        networkGate: any NetworkGating = LiveNetworkGate(),
        portionPreferenceLoader: @escaping @Sendable (FoodProductRef) throws -> FoodPortionPreference? = { _ in nil },
        onLogged: @escaping @MainActor () -> Void = {}
    ) {
        self.foodResolver = foodResolver
        self.manualMealService = manualMealService
        self.pendingImportService = pendingImportService
        self.networkGate = networkGate
        self.portionPreferenceLoader = portionPreferenceLoader
        self.onLogged = onLogged
    }

    var isBusy: Bool {
        if case .saving = phase {
            return true
        }
        return false
    }

    func refreshConnectivity() async {
        let nowOnline = await networkGate.isOnline()
        if !wasOnline && nowOnline {
            _ = await pendingImportService.resolvePendingImports()
            onLogged()
        }
        wasOnline = nowOnline
        isOnline = nowOnline
    }

    func start(_ mode: AddFoodEntryMode, bucket: MealBucket) {
        preferredBucket = bucket
        phase = .flow(mode)
    }

    func startSearch(bucket: MealBucket = .snacks) {
        start(.search, bucket: bucket)
    }

    func startBarcode(bucket: MealBucket = .snacks) {
        start(.barcode, bucket: bucket)
    }

    func startQuickAdd(bucket: MealBucket = .snacks) {
        start(.quickAdd, bucket: bucket)
    }

    func startAlcohol(bucket: MealBucket = .snacks) {
        start(.alcohol, bucket: bucket)
    }

    func cancel() {
        phase = .idle
    }

    func dismissError() {
        if case .failed = phase {
            phase = .idle
        }
    }

    func searchLocal(query: String) async throws -> [FoodSearchResult] {
        try await foodResolver.searchLocal(query: query)
    }

    func searchRemote(query: String) async throws -> [FoodSearchResult] {
        try await foodResolver.searchRemote(query: query)
    }

    func search(query: String) async throws -> [FoodSearchResult] {
        try await foodResolver.searchRemote(query: query)
    }

    func fetchRecents(limit: Int = 20) async -> [ResolvedFoodProduct] {
        (try? await foodResolver.fetchRecentProducts(limit: limit)) ?? []
    }

    func resolveBarcode(_ barcode: String) async throws -> ResolvedFoodProduct {
        try await foodResolver.resolveBarcode(barcode)
    }

    func portionDefaults(for product: ResolvedFoodProduct) -> FoodPortionDefaults {
        let storedPreference = try? portionPreferenceLoader(product.ref)
        return FoodPortionDefaultsResolver.defaults(for: product, storedPreference: storedPreference)
    }

    func logFood(
        product: ResolvedFoodProduct,
        grams: Double,
        servingLabel: String?,
        bucket: MealBucket,
        source: MealRecord.Source
    ) async {
        phase = .saving
        do {
            _ = try await manualMealService.logFood(
                product: product,
                grams: grams,
                servingLabel: servingLabel,
                bucket: bucket,
                source: source
            )
            HapticEngine.shared.play(.mealConfirmed)
            phase = .idle
            onLogged()
        } catch {
            phase = .failed(userMessage(for: error))
        }
    }

    func logQuickAdd(
        macros: FoodPortionMacros,
        label: String?,
        bucket: MealBucket
    ) async {
        phase = .saving
        do {
            _ = try await manualMealService.logQuickAdd(
                kilocalories: macros.energyKcal,
                proteinG: macros.proteinG,
                carbsG: macros.carbsG,
                fatG: macros.fatG,
                label: label,
                bucket: bucket
            )
            HapticEngine.shared.play(.mealConfirmed)
            phase = .idle
            onLogged()
        } catch {
            phase = .failed(quickAddMessage(for: error))
        }
    }

    func queueOfflineBarcode(
        barcode: String,
        bucket: MealBucket
    ) async {
        phase = .saving
        do {
            _ = try await pendingImportService.queueOfflineBarcode(
                barcode: barcode,
                bucket: bucket
            )
            HapticEngine.shared.play(.mealConfirmed)
            phase = .idle
            onLogged()
        } catch {
            phase = .failed("Could not save that barcode for later. Try again.")
        }
    }

    func logAlcohol(
        preset: AlcoholDrinkPreset,
        quantity: Int,
        bucket: MealBucket
    ) async {
        phase = .saving
        do {
            _ = try await manualMealService.logAlcohol(
                preset: preset,
                quantity: quantity,
                bucket: bucket
            )
            HapticEngine.shared.play(.mealConfirmed)
            phase = .idle
            onLogged()
        } catch {
            phase = .failed(alcoholMessage(for: error))
        }
    }

    private func userMessage(for error: Error) -> String {
        switch error {
        case ManualMealError.invalidPortion:
            "Enter a portion greater than zero."
        case FoodResolverError.offline:
            "Branded lookup needs a network connection. Try again when you are online."
        case FoodResolverError.notFound:
            "No product found for that barcode."
        default:
            "Could not save that food. Try again."
        }
    }

    private func quickAddMessage(for error: Error) -> String {
        switch error {
        case ManualMealError.invalidQuickAdd:
            "Enter calories greater than zero."
        default:
            "Could not save quick add. Try again."
        }
    }

    private func alcoholMessage(for error: Error) -> String {
        switch error {
        case ManualMealError.invalidAlcoholQuantity:
            "Choose at least one drink."
        default:
            "Could not save alcohol. Try again."
        }
    }
}

#if DEBUG
extension ManualFoodLogController {
    static func previewController(online: Bool) -> ManualFoodLogController {
        let store = try! PersistenceStore.inMemory()
        let foodResolver = FoodResolver(persistence: store)
        return ManualFoodLogController(
            foodResolver: foodResolver,
            manualMealService: ManualMealService(),
            pendingImportService: PendingFoodImportService(
                persistence: store,
                foodResolver: foodResolver,
                manualMealService: ManualMealService()
            ),
            networkGate: FixedNetworkGate(online: online)
        )
    }
}
#endif
