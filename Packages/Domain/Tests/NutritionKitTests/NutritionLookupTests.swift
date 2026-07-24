import Core
import Foundation
import Testing
@testable import NutritionKit

@Suite("NutritionLookup")
struct NutritionLookupTests {
    private let lookup = NutritionLookup()

    @Test("resolves at least 90% of athlete fixture items")
    func fixtureResolutionRate() {
        let items = [
            "grilled chicken breast",
            "white rice cooked",
            "cooking oil",
            "salmon grilled",
            "brown rice",
            "egg whole",
            "greek yogurt",
            "oatmeal",
            "banana",
            "broccoli",
            "sweet potato",
            "ground beef",
            "pasta cooked",
            "avocado",
            "whey protein",
            "almond butter",
            "cottage cheese",
            "tuna canned",
            "olive oil",
            "mixed greens salad"
        ]

        var nonFallback = 0
        for item in items {
            let match = lookup.resolve(item: item)
            #expect(match != nil)
            if match?.matchConfidence != .fallback {
                nonFallback += 1
            }
        }

        let rate = Double(nonFallback) / Double(items.count)
        #expect(rate >= 0.9)
    }

    @Test("chicken rice bowl decomposition aggregates expected totals")
    func chickenRiceBowlAggregation() {
        let items = [
            ("grilled chicken breast", 140.0, MealEstimate.Confidence.high),
            ("white rice cooked", 180.0, MealEstimate.Confidence.medium),
            ("cooking oil", 8.0, MealEstimate.Confidence.low)
        ]

        let lineItems = items.compactMap { name, grams, confidence -> MealLineItem? in
            guard let resolved = lookup.resolve(item: name) else { return nil }
            return MacroAggregator.lineItem(
                name: name,
                grams: grams,
                resolved: resolved,
                itemConfidence: confidence
            )
        }

        let estimate = MacroAggregator.sum(description: "Chicken rice bowl", lineItems: lineItems)

        #expect(estimate.lineItems.count == 3)
        #expect(estimate.caloriesKcal > 400)
        #expect(estimate.caloriesKcal < 900)
        #expect(estimate.proteinG > 30)
        #expect(estimate.confidence == .low)
    }
}
