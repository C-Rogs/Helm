import Core
import Foundation

public enum MacroAggregator: Sendable {
    public static func lineItem(
        name: String,
        grams: Double,
        resolved: ResolvedNutrition,
        itemConfidence: MealEstimate.Confidence
    ) -> MealLineItem {
        let scale = grams / 100.0
        let per100g = resolved.record.per100g
        let matchConfidence = confidence(from: resolved.matchConfidence, itemConfidence: itemConfidence)

        return MealLineItem(
            name: name,
            grams: grams,
            caloriesKcal: per100g.kcal * scale,
            proteinG: per100g.proteinG * scale,
            carbsG: per100g.carbsG * scale,
            fatG: per100g.fatG * scale,
            usdaMatchID: resolved.record.fdcId,
            matchConfidence: matchConfidence,
            cofidDescription: resolved.record.description
        )
    }

    public static func recomputeLineItem(_ item: MealLineItem, grams: Double, lookup: NutritionLookup) -> MealLineItem {
        guard let resolved = lookup.resolve(item: item.name) else {
            let scale = grams / max(item.grams, 1)
            return MealLineItem(
                name: item.name,
                grams: grams,
                caloriesKcal: item.caloriesKcal * scale,
                proteinG: item.proteinG * scale,
                carbsG: item.carbsG * scale,
                fatG: item.fatG * scale,
                usdaMatchID: item.usdaMatchID,
                matchConfidence: item.matchConfidence,
                cofidDescription: item.cofidDescription
            )
        }

        return lineItem(
            name: item.name,
            grams: grams,
            resolved: resolved,
            itemConfidence: item.matchConfidence
        )
    }

    public static func sum(
        description: String,
        lineItems: [MealLineItem],
        groundingWarnings: [String] = [],
        decompositionAuditJSON: String? = nil,
        visionDirectEstimate: MealEstimate.VisionMacroComparison? = nil
    ) -> MealEstimate {
        let calories = lineItems.reduce(0) { $0 + $1.caloriesKcal }
        let protein = lineItems.reduce(0) { $0 + $1.proteinG }
        let carbs = lineItems.reduce(0) { $0 + $1.carbsG }
        let fat = lineItems.reduce(0) { $0 + $1.fatG }
        let confidence = lineItems.map(\.matchConfidence).min(by: confidenceRank) ?? .medium

        return MealEstimate(
            description: description,
            caloriesKcal: calories.rounded(),
            proteinG: protein.rounded(to: 1),
            carbsG: carbs.rounded(to: 1),
            fatG: fat.rounded(to: 1),
            confidence: confidence,
            lineItems: lineItems,
            visionDirectEstimate: visionDirectEstimate,
            groundingWarnings: groundingWarnings,
            decompositionAuditJSON: decompositionAuditJSON
        )
    }

    private static func confidence(
        from match: ResolvedNutrition.MatchConfidence,
        itemConfidence: MealEstimate.Confidence
    ) -> MealEstimate.Confidence {
        switch match {
        case .exact, .synonym:
            return itemConfidence
        case .partial:
            return minConfidence(itemConfidence, .medium)
        case .fallback:
            return .low
        }
    }

    private static func confidenceRank(_ lhs: MealEstimate.Confidence, _ rhs: MealEstimate.Confidence) -> Bool {
        rank(lhs) < rank(rhs)
    }

    private static func rank(_ confidence: MealEstimate.Confidence) -> Int {
        switch confidence {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }

    private static func minConfidence(
        _ lhs: MealEstimate.Confidence,
        _ rhs: MealEstimate.Confidence
    ) -> MealEstimate.Confidence {
        rank(lhs) <= rank(rhs) ? lhs : rhs
    }
}

private extension Double {
    func rounded(to places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
