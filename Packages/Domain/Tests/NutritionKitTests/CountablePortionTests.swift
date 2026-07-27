import Testing
@testable import NutritionKit

@Suite("Countable portion")
struct CountablePortionTests {
    @Test("detects egg products")
    func detectsEggs() {
        let config = CountablePortion.detect(for: "Coop 6 large free range eggs")
        #expect(config?.kind == .egg)
        #expect(config?.hasSizeVariants == true)
    }

    @Test("detects branded bars")
    func detectsBars() {
        let config = CountablePortion.detect(
            for: "Grenade Carb Killa",
            suggestedGrams: 60,
            servingLabel: "1 bar"
        )
        #expect(config?.kind == .bar)
        #expect(config?.fixedUnitGrams == 60)
    }

    @Test("banana stays non-countable")
    func bananaNotCountable() {
        let config = CountablePortion.detect(for: "Banana, flesh only")
        #expect(config == nil)
    }

    @Test("formats serving label for multiple eggs")
    func formatsServingLabel() {
        let config = CountablePortionConfig(
            kind: .egg,
            sizeOptions: PortionOptionCatalog.unitSizeOptions(forKeyword: "egg"),
            unitNoun: "egg",
            pluralNoun: "eggs"
        )
        let label = CountablePortion.formatServingLabel(
            quantity: 3,
            sizeLabel: "1 large",
            config: config
        )
        #expect(label == "3 large eggs")
    }

    @Test("parses serving label back to quantity and size")
    func parsesServingLabel() {
        let config = CountablePortionConfig(
            kind: .egg,
            sizeOptions: PortionOptionCatalog.unitSizeOptions(forKeyword: "egg"),
            unitNoun: "egg",
            pluralNoun: "eggs"
        )
        let parsed = CountablePortion.parseServingLabel("3 large eggs", config: config)
        #expect(parsed?.quantity == 3)
        #expect(parsed?.sizeOption?.label == "1 large")
    }

    @Test("infers large size from pack name")
    func infersLargeFromPackName() {
        let config = CountablePortionConfig(
            kind: .egg,
            sizeOptions: PortionOptionCatalog.unitSizeOptions(forKeyword: "egg"),
            unitNoun: "egg",
            pluralNoun: "eggs"
        )
        let size = CountablePortion.inferDefaultSize(from: "Coop 6 large free range eggs", config: config)
        #expect(size?.label == "1 large")
    }

    @Test("pack weight is detected for egg cartons")
    func detectsPackWeight() {
        let config = CountablePortionConfig(
            kind: .egg,
            sizeOptions: PortionOptionCatalog.unitSizeOptions(forKeyword: "egg"),
            unitNoun: "egg",
            pluralNoun: "eggs"
        )
        #expect(CountablePortion.isLikelyPackWeight(300, config: config))
        #expect(CountablePortion.isLikelyPackWeight(50, config: config) == false)
    }
}
