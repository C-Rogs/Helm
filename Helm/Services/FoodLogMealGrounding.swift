import CoachLLM
import Core
import Foundation
import NutritionKit

enum FoodLogMealGrounding {
    static func groundedEstimate(from payload: FoodLogPayload) -> MealEstimate {
        if payload.hasIngredientBreakdown {
            let decomposition = MealDecomposition(
                payload: MealDecompositionPayload(
                    schemaVersion: CoachOutputSchemaVersion.mealDecompositionV1.rawValue,
                    mealDescription: payload.description ?? "Meal",
                    items: payload.items ?? [],
                    implicitFats: payload.implicitFats ?? [],
                    portionNotes: payload.portionNotes
                )
            )
            let estimate = GroundedPhotoMacroEstimator(vision: UnusedMealVision()).aggregate(decomposition)
            if !estimate.lineItems.isEmpty {
                return estimate
            }
            return proportionalFallback(from: payload)
        }

        return aggregateFallback(from: payload)
    }

    private static func proportionalFallback(from payload: FoodLogPayload) -> MealEstimate {
        let description = payload.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let mealName = description?.isEmpty == false ? description! : "Meal"
        let items = (payload.items ?? []) + (payload.implicitFats ?? [])
        let totalGrams = items.reduce(0) { $0 + max($1.estimatedGrams, 0) }
        let calories = payload.caloriesKcal ?? 0
        let protein = payload.proteinG ?? 0
        let carbs = payload.carbsG ?? 0
        let fat = payload.fatG ?? 0

        let lineItems: [MealLineItem]
        if totalGrams > 0, !items.isEmpty {
            lineItems = items.map { item in
                let share = max(item.estimatedGrams, 0) / totalGrams
                return MealLineItem(
                    name: item.name,
                    grams: item.estimatedGrams,
                    caloriesKcal: calories * share,
                    proteinG: protein * share,
                    carbsG: carbs * share,
                    fatG: fat * share,
                    matchConfidence: MealEstimate.Confidence(rawValue: item.confidence.rawValue) ?? .medium
                )
            }
        } else {
            lineItems = aggregateFallback(from: payload).lineItems
        }

        var warnings = ["Could not match ingredients to CoFID. Review each row before logging."]
        if let portionNotes = payload.portionNotes?.trimmingCharacters(in: .whitespacesAndNewlines),
           !portionNotes.isEmpty {
            warnings.append("Portion notes: \(portionNotes)")
        }

        return MacroAggregator.sum(
            description: mealName,
            lineItems: lineItems,
            groundingWarnings: warnings
        )
    }

    private static func aggregateFallback(from payload: FoodLogPayload) -> MealEstimate {
        let description = payload.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = description?.isEmpty == false ? description! : "Meal"
        let calories = payload.caloriesKcal ?? 0
        let protein = payload.proteinG ?? 0
        let carbs = payload.carbsG ?? 0
        let fat = payload.fatG ?? 0

        return MealEstimate(
            description: name,
            caloriesKcal: calories,
            proteinG: protein,
            carbsG: carbs,
            fatG: fat,
            confidence: .medium,
            lineItems: [
                MealLineItem(
                    name: name,
                    grams: 0,
                    caloriesKcal: calories,
                    proteinG: protein,
                    carbsG: carbs,
                    fatG: fat,
                    matchConfidence: .medium
                )
            ],
            groundingWarnings: payload.portionNotes.map { ["Portion notes: \($0)"] } ?? []
        )
    }
}

private struct UnusedMealVision: MealMacroVisionProviding {
    func decompose(imageJPEGData: Data, userNotes: String?) async throws -> MealDecomposition {
        throw CoachProviderError.requestFailed("Text-only grounding")
    }

    func estimateMacrosDirect(imageJPEGData: Data, userNotes: String?) async throws -> MealEstimate {
        throw CoachProviderError.requestFailed("Text-only grounding")
    }
}
