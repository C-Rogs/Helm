import Core
import Foundation
import NutritionKit

enum MealVisionDraftMapping {
    static func encodeAuditJSON(_ draft: MealVisionDraft) -> String? {
        let payload = MealVisionDraftPayload(
            schemaVersion: CoachOutputSchemaVersion.mealVisionDraftV1.rawValue,
            mealDescription: draft.mealDescription,
            items: draft.items,
            portionNotes: draft.portionNotes
        )
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    static func mealEstimate(
        from draft: MealVisionDraft,
        requiresRefinement: Bool,
        portionAssistWarning: String? = nil
    ) -> MealEstimate {
        let lineItems = draft.items.map(lineItem(from:))
        var warnings: [String] = []
        if let portionNotes = draft.portionNotes?.trimmingCharacters(in: .whitespacesAndNewlines),
           !portionNotes.isEmpty {
            warnings.append("Portion notes: \(portionNotes)")
        }
        if let portionAssistWarning {
            warnings.insert(portionAssistWarning, at: 0)
        }

        var estimate = MacroAggregator.sum(
            description: draft.mealDescription,
            lineItems: lineItems,
            groundingWarnings: warnings,
            decompositionAuditJSON: encodeAuditJSON(draft)
        )
        estimate.scanMode = .visionDirect
        estimate.requiresRefinement = requiresRefinement
        return estimate
    }

    static func draft(from estimate: MealEstimate) -> MealVisionDraft? {
        guard !estimate.lineItems.isEmpty else { return nil }
        let items = estimate.lineItems.map { item in
            MealVisionDraftPayload.Item(
                name: item.name,
                estimatedGrams: item.grams,
                caloriesKcal: item.caloriesKcal,
                proteinG: item.proteinG,
                carbsG: item.carbsG,
                fatG: item.fatG,
                portionMeta: item.portionMeta ?? "",
                confidence: MealVisionDraftPayload.Confidence(rawValue: item.matchConfidence.rawValue) ?? .medium
            )
        }
        return MealVisionDraft(
            mealDescription: estimate.description,
            items: items,
            portionNotes: nil
        )
    }

    private static func lineItem(from item: MealVisionDraftPayload.Item) -> MealLineItem {
        let confidence = MealEstimate.Confidence(rawValue: item.confidence.rawValue) ?? .medium
        return MealLineItem(
            name: item.name,
            grams: item.estimatedGrams,
            caloriesKcal: item.caloriesKcal,
            proteinG: item.proteinG,
            carbsG: item.carbsG,
            fatG: item.fatG,
            matchConfidence: confidence,
            portionMeta: item.portionMeta
        )
    }
}
