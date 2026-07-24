import Core
import Diagnostics
import Foundation
import OSLog
import Persistence

private let manualMealLog = Logger(subsystem: "com.cameronro.helm", category: "NutritionKit")

public enum ManualMealError: Error, Sendable, Equatable {
    case invalidPortion
    case invalidQuickAdd
    case invalidAlcoholQuantity
}

public struct ManualMealService: Sendable {
    private let writer: any MealHealthKitWriting
    private let localStore: ManualMealLocalStore?

    public init(
        writer: any MealHealthKitWriting = MealHealthKitWriter(),
        localStore: ManualMealLocalStore? = nil
    ) {
        self.writer = writer
        self.localStore = localStore
    }

    public func logFood(
        product: ResolvedFoodProduct,
        grams: Double,
        servingLabel: String? = nil,
        bucket: MealBucket,
        loggedAt: Date = Date(),
        mealID: String = UUID().uuidString,
        source: MealRecord.Source = .manual
    ) async throws -> SavedMealSamples {
        guard grams > 0 else {
            throw ManualMealError.invalidPortion
        }

        let macros = product.macros(forGrams: grams)
        let resolvedServing = servingLabel ?? product.servingLabel
        let lineItem = MealLineItemRecord(
            mealID: UUID(uuidString: mealID) ?? UUID(),
            foodRef: product.ref,
            grams: grams,
            servingLabel: resolvedServing,
            energyKcal: macros.energyKcal,
            proteinG: macros.proteinG,
            carbsG: macros.carbsG,
            fatG: macros.fatG,
            sortOrder: 0
        )

        return try await persist(
            PersistedManualMeal(
                name: product.ref.displayName,
                bucket: bucket,
                loggedAt: loggedAt,
                mealID: mealID,
                source: source,
                macros: macros,
                lineItems: [lineItem]
            )
        )
    }

    public func logQuickAdd(
        kilocalories: Double,
        label: String? = nil,
        bucket: MealBucket,
        loggedAt: Date = Date(),
        mealID: String = UUID().uuidString
    ) async throws -> SavedMealSamples {
        guard kilocalories > 0 else {
            throw ManualMealError.invalidQuickAdd
        }

        let trimmedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedLabel?.isEmpty == false ? trimmedLabel! : "Quick add"
        let macros = FoodPortionMacros(
            energyKcal: kilocalories,
            proteinG: 0,
            carbsG: 0,
            fatG: 0
        )

        return try await persist(
            PersistedManualMeal(
                name: name,
                bucket: bucket,
                loggedAt: loggedAt,
                mealID: mealID,
                source: .quickAdd,
                macros: macros
            )
        )
    }

    public func logAlcohol(
        preset: AlcoholDrinkPreset,
        quantity: Int,
        bucket: MealBucket,
        loggedAt: Date = Date(),
        mealID: String = UUID().uuidString
    ) async throws -> SavedMealSamples {
        guard quantity > 0 else {
            throw ManualMealError.invalidAlcoholQuantity
        }

        let macros = preset.macros(quantity: quantity)
        let name = quantity == 1 ? preset.displayName : "\(quantity) × \(preset.displayName)"

        return try await persist(
            PersistedManualMeal(
                name: name,
                bucket: bucket,
                loggedAt: loggedAt,
                mealID: mealID,
                source: .alcohol,
                macros: macros
            )
        )
    }

    private struct PersistedManualMeal: Sendable {
        let name: String
        let bucket: MealBucket
        let loggedAt: Date
        let mealID: String
        let source: MealRecord.Source
        let macros: FoodPortionMacros
        var lineItems: [MealLineItemRecord] = []
    }

    private func persist(_ meal: PersistedManualMeal) async throws -> SavedMealSamples {
        let request = MealWriteRequest(
            mealID: meal.mealID,
            name: meal.name,
            loggedAt: meal.loggedAt,
            caloriesKcal: meal.macros.energyKcal,
            proteinG: meal.macros.proteinG,
            carbsG: meal.macros.carbsG,
            fatG: meal.macros.fatG,
            mealSource: HelmHealthKitMetadata.mealSourceValue(for: meal.source)
        )

        do {
            let saved = try await writer.saveMeal(request)
            try localStore?.recordSavedMeal(
                request: request,
                saved: saved,
                bucket: meal.bucket,
                source: meal.source,
                lineItems: meal.lineItems
            )
            manualMealLog.debug("Manual meal saved mealID=\(saved.mealID, privacy: .public) source=\(meal.source.rawValue, privacy: .public)")
            return saved
        } catch {
            manualMealLog.error("Manual meal write failed: \(String(describing: type(of: error)), privacy: .public)")
            Task {
                await DiagnosticsLog.shared.capture(
                    error: error,
                    category: .nutritionKit,
                    message: "Manual meal HealthKit write failed"
                )
            }
            throw error
        }
    }
}
