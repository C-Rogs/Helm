import Core
import Foundation

public enum MealLineItemTemplateMapping {
    public static func lineItem(from record: MealLineItemRecord) -> MealLineItem {
        MealLineItem(
            name: record.foodRef.displayName,
            grams: record.grams,
            caloriesKcal: record.energyKcal,
            proteinG: record.proteinG,
            carbsG: record.carbsG,
            fatG: record.fatG,
            usdaMatchID: record.foodRef.cacheKey,
            matchConfidence: .high
        )
    }

    public static func record(from lineItem: MealLineItem, mealID: UUID, sortOrder: Int, servingLabel: String? = nil) -> MealLineItemRecord {
        MealLineItemRecord(
            mealID: mealID,
            foodRef: foodRef(from: lineItem),
            grams: lineItem.grams,
            servingLabel: servingLabel,
            energyKcal: lineItem.caloriesKcal,
            proteinG: lineItem.proteinG,
            carbsG: lineItem.carbsG,
            fatG: lineItem.fatG,
            sortOrder: sortOrder
        )
    }

    public static func foodRef(from lineItem: MealLineItem) -> FoodProductRef {
        if let cacheKey = lineItem.usdaMatchID,
           let ref = FoodProductRef(cacheKey: cacheKey, displayName: lineItem.name) {
            return ref
        }
        if let legacyID = lineItem.usdaMatchID, !legacyID.isEmpty {
            return FoodProductRef(origin: .cofid, externalID: legacyID, displayName: lineItem.name)
        }
        return FoodProductRef(
            origin: .custom,
            externalID: stableCustomID(for: lineItem.name),
            displayName: lineItem.name
        )
    }

    private static func stableCustomID(for name: String) -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var hasher = Hasher()
        hasher.combine(normalized)
        let hash = UInt64(bitPattern: Int64(hasher.finalize()))
        return String(format: "%016llx", hash)
    }
}
