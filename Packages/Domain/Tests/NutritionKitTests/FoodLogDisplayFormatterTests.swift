import Testing
@testable import NutritionKit

@Suite("Food log display formatter")
struct FoodLogDisplayFormatterTests {
    @Test("coop eggs use food title and rich detail")
    func coopEggsDisplay() {
        let title = FoodLogDisplayFormatter.primaryTitle(
            displayName: "Coop 6 large free range eggs",
            servingLabel: "3 large eggs"
        )
        let detail = FoodLogDisplayFormatter.secondaryDetail(
            displayName: "Coop 6 large free range eggs",
            servingLabel: "3 large eggs",
            grams: 150
        )

        #expect(title == "Eggs")
        #expect(detail == "3 large eggs · 150 g · Coop")
    }

    @Test("grenade bar keeps product title")
    func grenadeBarDisplay() {
        let title = FoodLogDisplayFormatter.primaryTitle(
            displayName: "Grenade Carb Killa",
            servingLabel: "2 bars"
        )
        let detail = FoodLogDisplayFormatter.secondaryDetail(
            displayName: "Grenade Carb Killa",
            servingLabel: "2 bars",
            grams: 120
        )

        #expect(title == "Grenade Carb Killa")
        #expect(detail == "2 bars · 120 g · Grenade")
    }

    @Test("meal header hidden for single line item")
    func singleLineItemHeader() {
        let show = FoodLogDisplayFormatter.shouldShowMealHeader(
            mealName: "Coop 6 large free range eggs",
            lineItems: [
                FoodLogDisplayFormatter.MealLineItemDisplayInput(
                    displayName: "Coop 6 large free range eggs",
                    servingLabel: "3 large eggs",
                    grams: 150
                )
            ]
        )
        #expect(show == false)
    }

    @Test("meal header shown for multi-ingredient meals")
    func multiLineItemHeader() {
        let show = FoodLogDisplayFormatter.shouldShowMealHeader(
            mealName: "Breakfast",
            lineItems: [
                FoodLogDisplayFormatter.MealLineItemDisplayInput(
                    displayName: "Rolled oats",
                    servingLabel: "80 g",
                    grams: 80
                ),
                FoodLogDisplayFormatter.MealLineItemDisplayInput(
                    displayName: "Banana, flesh only",
                    servingLabel: "1 medium",
                    grams: 118
                )
            ]
        )
        #expect(show == true)
    }

    @Test("parses brand from display name")
    func parsesBrand() {
        #expect(FoodLogDisplayFormatter.parseBrand(from: "Coop 6 large free range eggs") == "Coop")
        #expect(FoodLogDisplayFormatter.parseBrand(from: "Egg, whole, raw") == nil)
    }

    @Test("formatNumber does not trap on non-finite values")
    func formatNumberIsSafe() {
        #expect(FoodLogDisplayFormatter.formatNumber(35) == "35")
        #expect(FoodLogDisplayFormatter.formatNumber(34.9) == "34.9")
        #expect(FoodLogDisplayFormatter.formatNumber(.infinity) == "0")
        #expect(FoodLogDisplayFormatter.formatNumber(.nan) == "0")
    }
}
