import Core
import Foundation

/// Scales a photo-scan line from the original vision macros, not the last edit.
public enum VisionPortionScaler {
    public struct Base: Sendable, Equatable {
        public let grams: Double
        public let caloriesKcal: Double
        public let proteinG: Double
        public let carbsG: Double
        public let fatG: Double

        public init(grams: Double, caloriesKcal: Double, proteinG: Double, carbsG: Double, fatG: Double) {
            self.grams = grams
            self.caloriesKcal = caloriesKcal
            self.proteinG = proteinG
            self.carbsG = carbsG
            self.fatG = fatG
        }

        public init(item: MealLineItem) {
            self.init(
                grams: item.grams,
                caloriesKcal: item.caloriesKcal,
                proteinG: item.proteinG,
                carbsG: item.carbsG,
                fatG: item.fatG
            )
        }
    }

    public struct Edit: Sendable, Equatable {
        public let item: MealLineItem
        public let servingLabel: String
    }

    /// Nil when servings text does not parse. Caller keeps the previous row.
    public static func edit(
        name: String,
        base: Base,
        template: MealLineItem,
        servingsText: String,
        unitGrams: Double,
        unitLabel: String
    ) -> Edit? {
        guard let servings = PortionServings.parse(servingsText), servings > 0 else { return nil }
        let grams = PortionServings.totalGrams(servings: servings, unitGrams: unitGrams)
        let scale = grams / max(base.grams, 1)
        let item = MealLineItem(
            name: name,
            grams: grams,
            caloriesKcal: base.caloriesKcal * scale,
            proteinG: base.proteinG * scale,
            carbsG: base.carbsG * scale,
            fatG: base.fatG * scale,
            usdaMatchID: template.usdaMatchID,
            matchConfidence: template.matchConfidence,
            cofidDescription: template.cofidDescription,
            portionMeta: template.portionMeta
        )
        return Edit(
            item: item,
            servingLabel: PortionServings.displayLabel(servings: servings, servingSize: unitLabel)
        )
    }
}
