import Foundation

/// Compact P/C/F label for meal bucket cards and diary rows.
public enum MacroCompactFormatter {
    public static func compact(
        proteinGrams: Int,
        carbohydrateGrams: Int,
        fatGrams: Int
    ) -> String? {
        guard proteinGrams > 0 || carbohydrateGrams > 0 || fatGrams > 0 else { return nil }
        return "\(proteinGrams)P · \(carbohydrateGrams)C · \(fatGrams)F"
    }

    public static func compact(
        proteinGrams: Double?,
        carbohydrateGrams: Double?,
        fatGrams: Double?
    ) -> String? {
        compact(
            proteinGrams: Int((proteinGrams ?? 0).rounded()),
            carbohydrateGrams: Int((carbohydrateGrams ?? 0).rounded()),
            fatGrams: Int((fatGrams ?? 0).rounded())
        )
    }
}
