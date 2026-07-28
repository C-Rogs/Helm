import Core
import Foundation

enum MealPortionAssist {
    static func augmentedUserNotes(base: String?, assist: MealPortionAssistContext?) -> String? {
        guard let assist else { return base }
        let depthContext = assist.visionPromptContext
        let trimmed = base?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return depthContext
        }
        return "\(trimmed)\n\(depthContext)"
    }

    static func scaledDecomposition(
        _ decomposition: MealDecomposition,
        scaleFactor: Double
    ) -> MealDecomposition {
        func scale(_ item: MealDecompositionPayload.Item) -> MealDecompositionPayload.Item {
            MealDecompositionPayload.Item(
                name: item.name,
                estimatedGrams: (item.estimatedGrams * scaleFactor).rounded(),
                confidence: item.confidence
            )
        }

        let payload = MealDecompositionPayload(
            schemaVersion: CoachOutputSchemaVersion.mealDecompositionV1.rawValue,
            mealDescription: decomposition.mealDescription,
            items: decomposition.items.map(scale),
            implicitFats: decomposition.implicitFats.map(scale),
            portionNotes: decomposition.portionNotes
        )
        return MealDecomposition(payload: payload)
    }

    static func lidarWarning(for assist: MealPortionAssistContext) -> String {
        let pct = Int(((assist.gramScaleFactor - 1) * 100).rounded())
        guard pct != 0 else {
            return "LiDAR depth matched reference distance; grams unchanged."
        }
        let direction = pct > 0 ? "increased" : "decreased"
        return "LiDAR depth assist \(direction) gram estimates by \(abs(pct))%."
    }
}
