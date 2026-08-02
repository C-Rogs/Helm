import Core
import Diagnostics
import Foundation
import OSLog
import Persistence

private let manualMealLog = Logger(subsystem: "com.cameronro.helm", category: "NutritionKit")

public enum ManualMealError: Error, Sendable, Equatable, LocalizedError {
    case invalidPortion
    case invalidQuickAdd
    case invalidAlcoholQuantity
    case mealNotFound
    case nothingToDelete

    public var errorDescription: String? {
        switch self {
        case .invalidPortion:
            "Invalid portion."
        case .invalidQuickAdd:
            "Calories must be greater than zero."
        case .invalidAlcoholQuantity:
            "Alcohol quantity must be greater than zero."
        case .mealNotFound:
            "That meal was not found (it may already be deleted)."
        case .nothingToDelete:
            "No meals found to delete for that day."
        }
    }
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
        helmDay: HelmDay? = nil,
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
                helmDay: helmDay,
                mealID: mealID,
                source: source,
                macros: macros,
                lineItems: [lineItem]
            )
        )
    }

    public func logQuickAdd(
        kilocalories: Double,
        proteinG: Double = 0,
        carbsG: Double = 0,
        fatG: Double = 0,
        label: String? = nil,
        bucket: MealBucket,
        loggedAt: Date = Date(),
        helmDay: HelmDay? = nil,
        mealID: String = UUID().uuidString
    ) async throws -> SavedMealSamples {
        guard kilocalories > 0 else {
            throw ManualMealError.invalidQuickAdd
        }

        let trimmedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedLabel?.isEmpty == false ? trimmedLabel! : "Quick add"
        let macros = FoodPortionMacros(
            energyKcal: kilocalories,
            proteinG: max(0, proteinG),
            carbsG: max(0, carbsG),
            fatG: max(0, fatG)
        )

        return try await persist(
            PersistedManualMeal(
                name: name,
                bucket: bucket,
                loggedAt: loggedAt,
                helmDay: helmDay,
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
        helmDay: HelmDay? = nil,
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
                helmDay: helmDay,
                mealID: mealID,
                source: .alcohol,
                macros: macros
            )
        )
    }

    public func logCompositeMeal(
        name: String,
        bucket: MealBucket,
        lineItems: [MealLineItemRecord],
        loggedAt: Date = Date(),
        mealID: String = UUID().uuidString,
        source: MealRecord.Source,
        overrideMacros: FoodPortionMacros? = nil
    ) async throws -> SavedMealSamples {
        let macros: FoodPortionMacros
        if let overrideMacros {
            macros = overrideMacros
        } else if lineItems.isEmpty {
            throw ManualMealError.invalidPortion
        } else {
            macros = FoodPortionMacros(
                energyKcal: lineItems.reduce(0) { $0 + $1.energyKcal },
                proteinG: lineItems.reduce(0) { $0 + $1.proteinG },
                carbsG: lineItems.reduce(0) { $0 + $1.carbsG },
                fatG: lineItems.reduce(0) { $0 + $1.fatG }
            )
        }
        guard macros.energyKcal > 0 || !lineItems.isEmpty else {
            throw ManualMealError.invalidPortion
        }

        return try await persist(
            PersistedManualMeal(
                name: name,
                bucket: bucket,
                loggedAt: loggedAt,
                helmDay: nil,
                mealID: mealID,
                source: source,
                macros: macros,
                lineItems: lineItems
            )
        )
    }

    public func updateMeal(
        mealID: UUID,
        name: String,
        bucket: MealBucket,
        loggedAt: Date,
        macros: FoodPortionMacros,
        lineItems: [MealLineItemRecord],
        source: MealRecord.Source
    ) async throws -> SavedMealSamples {
        guard let existing = try localStore?.fetchMeal(id: mealID) else {
            throw ManualMealError.mealNotFound
        }

        let mealIDString = mealID.uuidString.lowercased()
        try await writer.deleteMeal(mealID: mealIDString)

        let request = MealWriteRequest(
            mealID: mealIDString,
            name: name,
            loggedAt: loggedAt,
            caloriesKcal: macros.energyKcal,
            proteinG: macros.proteinG,
            carbsG: macros.carbsG,
            fatG: macros.fatG,
            mealSource: HelmHealthKitMetadata.mealSourceValue(for: source)
        )

        do {
            let saved = try await writer.saveMeal(request)
            try localStore?.updateSavedMeal(
                mealID: mealID,
                previousHelmDay: existing.helmDay,
                request: request,
                saved: saved,
                bucket: bucket,
                source: source,
                lineItems: lineItems
            )
            manualMealLog.debug("Manual meal updated mealID=\(saved.mealID, privacy: .public)")
            return saved
        } catch {
            manualMealLog.error("Manual meal update failed: \(String(describing: type(of: error)), privacy: .public)")
            Task {
                await DiagnosticsLog.shared.capture(
                    error: error,
                    category: .nutritionKit,
                    message: "Manual meal HealthKit rewrite failed"
                )
            }
            throw error
        }
    }

    public func deleteMeal(mealID: UUID) async throws {
        let mealIDString = mealID.uuidString.lowercased()
        try await writer.deleteMeal(mealID: mealIDString)
        guard try localStore?.deleteMeal(id: mealID) != nil else {
            throw ManualMealError.mealNotFound
        }
        manualMealLog.debug("Manual meal deleted mealID=\(mealIDString, privacy: .public)")
    }

    private struct PersistedManualMeal: Sendable {
        let name: String
        let bucket: MealBucket
        let loggedAt: Date
        let helmDay: HelmDay?
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
            helmDay: meal.helmDay,
            caloriesKcal: meal.macros.energyKcal,
            proteinG: meal.macros.proteinG,
            carbsG: meal.macros.carbsG,
            fatG: meal.macros.fatG,
            mealSource: HelmHealthKitMetadata.mealSourceValue(for: meal.source)
        )

        var saved: SavedMealSamples?
        if let localStore {
            do {
                saved = try await writer.saveMeal(request)
            } catch {
                manualMealLog.error(
                    "Manual meal HealthKit write failed: \(String(describing: type(of: error)), privacy: .public)"
                )
                Task {
                    await DiagnosticsLog.shared.capture(
                        error: error,
                        category: .nutritionKit,
                        message: "Manual meal HealthKit write failed; saving locally only"
                    )
                }
            }

            let resolvedSaved = saved ?? SavedMealSamples.localOnly(mealID: meal.mealID)
            try localStore.recordSavedMeal(
                request: request,
                saved: resolvedSaved,
                bucket: meal.bucket,
                source: meal.source,
                lineItems: meal.lineItems
            )
            manualMealLog.debug(
                "Manual meal saved mealID=\(resolvedSaved.mealID, privacy: .public) source=\(meal.source.rawValue, privacy: .public) hk=\(saved != nil, privacy: .public)"
            )
            return resolvedSaved
        }

        do {
            let hkSaved = try await writer.saveMeal(request)
            manualMealLog.debug("Manual meal saved mealID=\(hkSaved.mealID, privacy: .public) source=\(meal.source.rawValue, privacy: .public)")
            return hkSaved
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
