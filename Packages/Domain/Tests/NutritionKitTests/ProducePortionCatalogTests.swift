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
}
