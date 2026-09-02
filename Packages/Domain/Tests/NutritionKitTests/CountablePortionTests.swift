import Testing
@testable import NutritionKit

@Suite("Countable portion")
struct CountablePortionTests {
    @Test("serving labelled whole becomes a one-unit countable")
    func detectsWholeServing() {
        let config = CountablePortion.detect(
            for: "Tesco avocado",
            suggestedGrams: 170,
            servingLabel: "1 whole"
        )
        #expect(config?.kind == .serving)
        #expect(config?.unitNoun == "whole")
        #expect(config?.fixedUnitGrams == 170)
        let label = CountablePortion.formatServingLabel(
            quantity: 1,
            sizeLabel: "1 whole",
            config: config!
        )
        #expect(label == "1 whole")
    }

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
        let withMedium = CountablePortion.detect(
            for: "Banana, flesh only",
            suggestedGrams: 118,
            servingLabel: "1 medium"
        )
        #expect(withMedium == nil)
    }

    @Test("gram-style serving becomes one whole unit")
    func detectsGramServingAsWhole() {
        let config = CountablePortion.detect(
            for: "Tesco avocado",
            suggestedGrams: 170,
            servingLabel: "170 g"
        )
        #expect(config?.kind == .serving)
        #expect(config?.unitNoun == "whole")
        #expect(config?.fixedUnitGrams == 170)
    }

    @Test("apple produce is countable as one whole")
    func detectsAppleAsWhole() {
        let config = CountablePortion.detect(for: "Apple, eating")
        #expect(config?.kind == .serving)
        #expect(config?.unitNoun == "whole")
        #expect(config?.fixedUnitGrams == 182)
        let label = CountablePortion.formatServingLabel(
            quantity: 1,
            sizeLabel: "1 whole",
            config: config!
        )
        #expect(label == "1 whole")
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

    @Test("gram serving size is one unit not a portion count")
    func gramServingIsNotQuantity() {
        let config = CountablePortion.detect(
            for: "PhD Smart Protein Bar",
            suggestedGrams: 35,
            servingLabel: "35 g"
        )
        #expect(config?.kind == .bar)
        #expect(config?.fixedUnitGrams == 35)

        let parsed = CountablePortion.parseServingLabel("35 g", config: config!)
        #expect(parsed?.quantity == 1)

        let parenthetical = CountablePortion.parseServingLabel("60 g (1 bar)", config: config!)
        #expect(parenthetical?.quantity == 1)
    }

    @Test("packaged gram serving is one whole not a count")
    func packagedGramServingIsOneWhole() {
        let config = CountablePortion.detect(
            for: "Grenade Carb Killa",
            suggestedGrams: 35,
            servingLabel: "35 g"
        )
        #expect(config?.kind == .serving)
        #expect(config?.fixedUnitGrams == 35)
        let parsed = CountablePortion.parseServingLabel("35 g", config: config!)
        #expect(parsed?.quantity == 1)
    }

    @Test("count in serving label divides total grams into unit grams")
    func servingCountDividesTotalGrams() {
        let bar = CountablePortion.detect(
            for: "PhD Smart Protein Bar",
            suggestedGrams: 1190,
            servingLabel: "34 bars"
        )
        #expect(bar?.fixedUnitGrams == 35)

        let whole = CountablePortion.detect(
            for: "Grenade Carb Killa",
            suggestedGrams: 1190,
            servingLabel: "34 whole"
        )
        #expect(whole?.kind == .serving)
        #expect(whole?.fixedUnitGrams == 35)

        let scoop = CountablePortion.detect(
            for: "Whey protein",
            suggestedGrams: 90,
            servingLabel: "3 scoops"
        )
        #expect(scoop?.kind == .scoop)
        #expect(scoop?.fixedUnitGrams == 30)

        let apple = CountablePortion.detect(
            for: "Apple, eating",
            suggestedGrams: 546,
            servingLabel: "3 whole"
        )
        #expect(apple?.fixedUnitGrams == 182)
    }

    @Test("gram serving is one unit for yogurt and packaged food")
    func gramServingIsOneUnitAcrossKinds() {
        let yogurt = CountablePortion.detect(
            for: "Fage Total yoghurt",
            suggestedGrams: 125,
            servingLabel: "125 g"
        )
        #expect(yogurt?.kind == .pot)
        #expect(CountablePortion.parseServingLabel("125 g", config: yogurt!)?.quantity == 1)

        let scoop = CountablePortion.detect(
            for: "Impact Whey",
            suggestedGrams: 30,
            servingLabel: "30 g scoop"
        )
        #expect(scoop?.kind == .scoop)
        #expect(CountablePortion.parseServingLabel("30 g scoop", config: scoop!)?.quantity == 1)
    }

    @Test("stepper range expands to hold an oversized count")
    func stepperRangeHoldsOversizedCount() {
        #expect(CountablePortion.quantityStepperRange(for: 1) == 1 ... 24)
        #expect(CountablePortion.quantityStepperRange(for: 35) == 1 ... 35)
        #expect(CountablePortion.clampedQuantity(fromDouble: .infinity) == 1)
    }
}
