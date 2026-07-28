import Core
import Foundation
import NutritionKit

public struct GroundedPhotoMacroEstimator: Sendable {
    private let vision: any MealVisionProviding
    private let lookup: NutritionLookup

    public init(vision: any MealVisionProviding, lookup: NutritionLookup = NutritionLookup()) {
        self.vision = vision
        self.lookup = lookup
    }

    public func estimateMacros(imageJPEGData: Data, userNotes: String?) async throws -> MealEstimate {
        let decomposition = try await vision.decompose(imageJPEGData: imageJPEGData, userNotes: userNotes)
        return aggregate(decomposition)
    }

    public func aggregate(_ decomposition: MealDecomposition) -> MealEstimate {
        let allItems = decomposition.items + decomposition.implicitFats
        let lineItems = allItems.compactMap { item -> MealLineItem? in
            guard let resolved = lookup.resolve(item: item.name) else { return nil }
            let confidence = MealEstimate.Confidence(rawValue: item.confidence.rawValue) ?? .medium
            return MacroAggregator.lineItem(
                name: item.name,
                grams: item.estimatedGrams,
                resolved: resolved,
                itemConfidence: confidence
            )
        }

        return MacroAggregator.sum(description: decomposition.mealDescription, lineItems: lineItems)
    }
}

extension GroundedPhotoMacroEstimator: MealMacroEstimating {}
