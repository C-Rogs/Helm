import NutritionKit
import Testing

@Suite("Macro compact formatter")
struct MacroCompactFormatterTests {
    @Test("formats bucket totals with middle dots")
    func compactMacros() {
        #expect(
            MacroCompactFormatter.compact(
                proteinGrams: 18,
                carbohydrateGrams: 62,
                fatGrams: 9
            ) == "18P · 62C · 9F"
        )
    }

    @Test("returns nil when all macros are zero")
    func emptyMacros() {
        #expect(
            MacroCompactFormatter.compact(
                proteinGrams: 0,
                carbohydrateGrams: 0,
                fatGrams: 0
            ) == nil
        )
        #expect(
            MacroCompactFormatter.compact(
                proteinGrams: nil,
                carbohydrateGrams: nil,
                fatGrams: nil
            ) == nil
        )
    }
}
