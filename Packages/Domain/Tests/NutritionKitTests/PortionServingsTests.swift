import Testing
@testable import NutritionKit

@Suite("Portion servings")
struct PortionServingsTests {
    @Test("half a bar is 30 g")
    func halfServing() {
        #expect(PortionServings.totalGrams(servings: 0.5, unitGrams: 60) == 30)
        #expect(PortionServings.format(0.5) == "0.5")
        #expect(PortionServings.displayLabel(servings: 0.5, servingSize: "1 bar") == "0.5 x 1 bar")
        #expect(PortionServings.displayLabel(servings: 1, servingSize: "1 bar") == "1 bar")
    }

    @Test("gram scale uses 1 g times the weight")
    func gramScale() {
        #expect(PortionServings.servings(grams: 173, unitGrams: 1) == 173)
        #expect(PortionServings.parse("173") == 173)
    }

    @Test("rejects zero and junk")
    func parseGuards() {
        #expect(PortionServings.parse("0") == nil)
        #expect(PortionServings.parse("nope") == nil)
        #expect(PortionServings.parse("1,5") == 1.5)
    }
}
