import Core
import Testing
@testable import NutritionKit

@Suite("Vision portion scaler")
struct VisionPortionScalerTests {
    private func template(grams: Double = 100, kcal: Double = 200) -> MealLineItem {
        MealLineItem(
            name: "Chicken",
            grams: grams,
            caloriesKcal: kcal,
            proteinG: 30,
            carbsG: 0,
            fatG: 8,
            matchConfidence: .medium
        )
    }

    @Test("doubling servings doubles vision calories from the scan base")
    func doublesFromScanBase() {
        let item = template()
        let base = VisionPortionScaler.Base(item: item)
        let once = VisionPortionScaler.edit(
            name: item.name,
            base: base,
            template: item,
            servingsText: "2",
            unitGrams: 100,
            unitLabel: "100 g"
        )
        #expect(once?.item.grams == 200)
        #expect(once?.item.caloriesKcal == 400)
        #expect(once?.item.proteinG == 60)

        let again = VisionPortionScaler.edit(
            name: item.name,
            base: base,
            template: once?.item ?? item,
            servingsText: "1",
            unitGrams: 100,
            unitLabel: "100 g"
        )
        #expect(again?.item.caloriesKcal == 200)
        #expect(again?.item.grams == 100)
    }

    @Test("invalid servings text does not produce a new row")
    func invalidServingsKeepsPriorRow() {
        let item = template()
        let edit = VisionPortionScaler.edit(
            name: item.name,
            base: VisionPortionScaler.Base(item: item),
            template: item,
            servingsText: "nope",
            unitGrams: 200,
            unitLabel: "200 g"
        )
        #expect(edit == nil)
    }
}
