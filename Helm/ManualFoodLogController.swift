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

    private let foodResolver: FoodResolver
    private let manualMealService: ManualMealService
    private let networkGate: any NetworkGating
    private let portionPreferenceLoader: @Sendable (FoodProductRef) throws -> FoodPortionPreference?
    private let onLogged: @MainActor () -> Void

    init(
        foodResolver: FoodResolver,
        manualMealService: ManualMealService,
        networkGate: any NetworkGating = LiveNetworkGate(),
        portionPreferenceLoader: @escaping @Sendable (FoodProductRef) throws -> FoodPortionPreference? = { _ in nil },
        onLogged: @escaping @MainActor () -> Void = {}
    ) {
        self.foodResolver = foodResolver
        self.manualMealService = manualMealService
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
        isOnline = await networkGate.isOnline()
    }

    func startSearch() {
        phase = .flow(.search)
    }

    func startBarcode() {
        phase = .flow(.barcode)
    }

    func startQuickAdd() {
        phase = .flow(.quickAdd)
    }

    func startAlcohol() {
        phase = .flow(.alcohol)
    }

    func cancel() {
        phase = .idle
    }

    func dismissError() {
        if case .failed = phase {
            phase = .idle
        }
    }

    func search(query: String) async throws -> [FoodSearchResult] {
        try await foodResolver.search(query: query)
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
        kilocalories: Double,
        label: String?,
        bucket: MealBucket
    ) async {
        phase = .saving
        do {
            _ = try await manualMealService.logQuickAdd(
                kilocalories: kilocalories,
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
        ManualFoodLogController(
            foodResolver: FoodResolver(persistence: try! PersistenceStore.inMemory()),
            manualMealService: ManualMealService(),
            networkGate: FixedNetworkGate(online: online)
        )
    }
}
#endif
