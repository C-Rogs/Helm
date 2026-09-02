import Testing
@testable import NutritionKit

@Suite("Portion option catalog")
struct ProducePortionCatalogTests {
    @Test("apple has small medium large options")
    func applePortions() {
        let options = PortionOptionCatalog.options(for: "Apple, eating")
        #expect(options.count >= 3)
        #expect(options.contains { $0.label == "1 medium" })
    }

    @Test("sweetcorn includes ear portion")
    func sweetcornEar() {
        let options = PortionOptionCatalog.options(for: "Sweetcorn, kernels")
        #expect(options.contains { $0.label == "1 ear" })
        #expect(options.first { $0.label == "1 ear" }?.grams == 90)
    }

    @Test("unknown food still gets gram presets")
    func universalGramPresets() {
        let options = PortionOptionCatalog.options(for: "Sourdough bread, crusty")
        #expect(!options.isEmpty)
        #expect(options.contains { $0.label.contains("slice") || $0.label.contains("g") })
    }

    @Test("branded serving is first chip")
    func brandedServingFirst() {
        let options = PortionOptionCatalog.options(
            for: "Grenade Carb Killa",
            origin: .openFoodFacts,
            suggestedGrams: 60,
            servingLabel: "1 bar"
        )
        #expect(options.first?.label == "1 bar")
        #expect(options.first?.grams == 60)
    }

    @Test("weight-only serving still offers one whole unit")
    func wholeUnitChipForGramServing() {
        let options = PortionOptionCatalog.options(
            for: "Tesco avocado",
            origin: .openFoodFacts,
            suggestedGrams: 170,
            servingLabel: "170 g"
        )
        #expect(options.first?.label == "1 whole")
        #expect(options.first?.grams == 170)
    }

    @Test("apple produce offers one whole before size chips")
    func appleWholeChipFirst() {
        let options = PortionOptionCatalog.options(for: "Apple, eating")
        #expect(options.first?.label == "1 whole")
        #expect(options.contains { $0.label == "1 medium" })
    }

    @Test("serving menu always includes 1 g for scale logging")
    func servingMenuIncludesGram() {
        let menu = PortionOptionCatalog.servingMenu(
            for: "Grenade Carb Killa",
            origin: .openFoodFacts,
            suggestedGrams: 60,
            servingLabel: "1 bar"
        )
        #expect(menu.contains { $0.label == "1 bar" && $0.grams == 60 })
        #expect(menu.contains { $0.label == "1 g" && $0.grams == 1 })
        #expect(menu.contains { $0.label == "100 g" && $0.grams == 100 })
    }
}
