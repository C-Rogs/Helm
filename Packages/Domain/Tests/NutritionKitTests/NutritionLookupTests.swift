import Core
import Foundation
import Testing
@testable import NutritionKit

@Suite("NutritionLookup")
struct NutritionLookupTests {
    private let lookup = NutritionLookup()

    @Test("resolves at least 90% of UK fixture items")
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

    @Test("renaming a line item re-resolves macros from CoFID lookup")
    func renameLineItemReResolvesMacros() {
        let chicken = lookup.resolve(item: "grilled chicken breast")
        #expect(chicken != nil)
        guard let chicken else { return }

        let original = MacroAggregator.lineItem(
            name: "pistachio spread",
            grams: 30,
            resolved: chicken,
            itemConfidence: .medium
        )

        let almond = lookup.resolve(item: "almond butter")
        #expect(almond != nil)
        let renamedItem = MealLineItem(
            name: "almond butter",
            grams: original.grams,
            caloriesKcal: original.caloriesKcal,
            proteinG: original.proteinG,
            carbsG: original.carbsG,
            fatG: original.fatG,
            usdaMatchID: original.usdaMatchID,
            matchConfidence: original.matchConfidence
        )
        let renamed = MacroAggregator.recomputeLineItem(
            renamedItem,
            grams: 30,
            lookup: lookup
        )

        #expect(renamed.name == "almond butter")
        #expect(renamed.caloriesKcal != original.caloriesKcal)
        #expect(renamed.usdaMatchID == almond?.record.fdcId)
    }

    @Test("apple search prefers whole fruit over juice variants")
    func appleSearchRanking() {
        let suggestions = lookup.suggestionNames(matching: "apple", limit: 10)
        #expect(!suggestions.isEmpty)
        let first = suggestions[0].lowercased()
        #expect(first.contains("apple"))
        #expect(!first.contains("juice"))
    }

    @Test("food suggestions return prefix matches")
    func foodSuggestions() {
        let suggestions = lookup.suggestionNames(matching: "almond")
        #expect(suggestions.contains { $0.lowercased().contains("almond") })
    }

    @Test("multi-word queries match token intersections")
    func multiWordSuggestions() {
        let suggestions = lookup.suggestionNames(matching: "greek yogurt", limit: 10)
        #expect(!suggestions.isEmpty)
        #expect(suggestions.contains { $0.lowercased().contains("greek") && $0.lowercased().contains("yogurt") })
    }

    @Test("protein yogurt has no generic CoFID hits")
    func brandedStyleQueryMissesCoFID() {
        let suggestions = lookup.suggestionNames(matching: "protein yogurt", limit: 10)
        #expect(suggestions.isEmpty)
    }

    @Test("gin and tonic variants miss weak CoFID so branded search can run")
    func ginAndTonicVariantsMissCoFID() {
        let queries = [
            "gin and tonic",
            "diet gin and tonic",
            "gin and tonic with diet tonic",
            "skinny gin and tonic",
            "rhubarb gin and tonic",
            "g and t",
            "G&T",
            "gin",
        ]
        for query in queries {
            let suggestions = lookup.suggestionNames(matching: query, limit: 20)
            #expect(
                suggestions.isEmpty,
                "Expected no weak CoFID flood for \(query), got \(suggestions.prefix(5))"
            )
        }
    }

    @Test("gin alone does not match ginger")
    func ginDoesNotMatchGinger() {
        let suggestions = lookup.suggestionNames(matching: "gin", limit: 10)
        #expect(!suggestions.contains { $0.lowercased().contains("ginger") })
    }

    @Test("cooked fish does not match bacon via modifier tokens")
    func cookedFishAvoidsBaconMatch() {
        let match = lookup.resolve(item: "cooked fish meat no skin")
        #expect(match != nil)
        guard let match else { return }
        #expect(!match.record.description.lowercased().contains("bacon"))
        let lineItem = MacroAggregator.lineItem(
            name: "cooked fish meat",
            grams: 90,
            resolved: match,
            itemConfidence: .medium
        )
        #expect(lineItem.caloriesKcal < 200)
    }

    @Test("napa cabbage resolves to chinese cabbage")
    func napaCabbageResolvesCorrectly() {
        let match = lookup.resolve(item: "napa cabbage")
        #expect(match?.record.description.lowercased().contains("chinese") == true)
        let lineItem = MacroAggregator.lineItem(
            name: "napa cabbage",
            grams: 100,
            resolved: match!,
            itemConfidence: .high
        )
        #expect(lineItem.caloriesKcal < 40)
    }

    @Test("sliced cucumbers resolves to cucumber not avocado")
    func slicedCucumbersAvoidAvocado() {
        let match = lookup.resolve(item: "sliced cucumbers")
        #expect(match?.record.fdcId == "13-523")
        #expect(!match!.record.description.lowercased().contains("avocado"))
    }

    @Test("sliced cucumbers resolves to cucumber not generic dish")
    func slicedCucumbersResolveToCucumber() {
        let match = lookup.resolve(item: "sliced cucumbers")
        #expect(match != nil)
        guard let match else { return }
        #expect(match.record.fdcId == "13-523")
        #expect(match.matchConfidence != .fallback)

        let lineItem = MacroAggregator.lineItem(
            name: "sliced cucumbers",
            grams: 75,
            resolved: match,
            itemConfidence: .high
        )
        #expect(lineItem.caloriesKcal < 20)
        #expect(!lineItem.usesGenericCofidFallback)
    }

    @Test("prawn boiled prefers plain prawns over prawn toast")
    func prawnBoiledNotToast() {
        let match = lookup.resolve(item: "prawn, boiled")
        #expect(match != nil)
        guard let match else { return }
        let description = match.record.description.lowercased()
        #expect(description.contains("prawn"))
        #expect(!description.contains("toast"))
        #expect(!description.contains("cracker"))
        #expect(!description.contains("curry"))
    }

    @Test("CoFID attribution exposes OGL notice")
    func cofidAttribution() {
        #expect(CoFIDAttribution.licenceNotice.contains("Open Government Licence"))
        #expect(CoFIDAttribution.sourceURL.contains("cofid"))
    }

    @Test("tokensEquivalent is plural-aware without substring matches")
    func tokensEquivalentBoundaries() {
        #expect(NutritionLookup.tokensEquivalent("gin", "gin"))
        #expect(NutritionLookup.tokensEquivalent("egg", "eggs"))
        #expect(!NutritionLookup.tokensEquivalent("gin", "ginger"))
        #expect(!NutritionLookup.tokensEquivalent("tonic", "gin"))
    }
}
