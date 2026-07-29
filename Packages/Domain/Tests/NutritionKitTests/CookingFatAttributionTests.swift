import Testing
@testable import NutritionKit

@Suite("Cooking fat attribution")
struct CookingFatAttributionTests {
    @Test("fried chips are included in CoFID row")
    func friedChipsIncludedInRow() {
        let attribution = CookingFatAttributionClassifier.classify(
            itemName: "Potato chips, fried in commercial oil",
            cofidDescription: "Potato chips, fried in commercial oil, from takeaway fish and chip shops",
            fatGPer100g: 14.2
        )
        #expect(attribution == .includedInRow)
    }

    @Test("grilled chicken is additive candidate")
    func grilledChickenAdditive() {
        let attribution = CookingFatAttributionClassifier.classify(
            itemName: "grilled chicken breast",
            cofidDescription: "Chicken, breast, grilled without skin, meat only",
            fatGPer100g: 2.2
        )
        #expect(attribution == .additiveCandidate)
    }

    @Test("salmon is intrinsically fatty")
    func salmonIntrinsic() {
        let attribution = CookingFatAttributionClassifier.classify(
            itemName: "grilled salmon fillet",
            cofidDescription: "Salmon, flesh only, grilled",
            fatGPer100g: 12.4
        )
        #expect(attribution == .intrinsic)
    }
}

@Suite("Cooking fat reconciler")
struct CookingFatReconcilerTests {
    @Test("drops cooking oil when fried chips already include fat")
    func dropsOilForFishAndChips() {
        let items = [
            CookingFatReconciler.ResolvedItem(
                name: "battered cod",
                attribution: .includedInRow,
                cofidDescription: "Fish, in batter, fried in blended oil"
            ),
            CookingFatReconciler.ResolvedItem(
                name: "Potato chips, fried in commercial oil",
                attribution: .includedInRow,
                cofidDescription: "Potato chips, fried in commercial oil, from takeaway fish and chip shops"
            ),
        ]
        let implicitFats = [
            CookingFatReconciler.ImplicitFat(name: "cooking oil", grams: 12)
        ]

        let result = CookingFatReconciler.reconcile(items: items, implicitFats: implicitFats)

        #expect(result.keptImplicitFats.isEmpty)
        #expect(result.droppedImplicitFats.count == 1)
        #expect(result.warnings.isEmpty == false)
    }

    @Test("keeps cooking oil for lean chicken and rice bowl")
    func keepsOilForLeanBowl() {
        let items = [
            CookingFatReconciler.ResolvedItem(
                name: "grilled chicken breast",
                attribution: .additiveCandidate,
                cofidDescription: "Chicken, breast, grilled without skin, meat only"
            ),
            CookingFatReconciler.ResolvedItem(
                name: "white rice cooked",
                attribution: .additiveCandidate,
                cofidDescription: "Rice, white, long grain, boiled in unsalted water"
            ),
        ]
        let implicitFats = [
            CookingFatReconciler.ImplicitFat(name: "cooking oil", grams: 8)
        ]

        let result = CookingFatReconciler.reconcile(items: items, implicitFats: implicitFats)

        #expect(result.keptImplicitFats.count == 1)
        #expect(result.droppedImplicitFats.isEmpty)
    }

    @Test("keeps dressing when salad shares plate with fried food")
    func keepsDressingOnMixedPlate() {
        let items = [
            CookingFatReconciler.ResolvedItem(
                name: "Potato chips, fried in commercial oil",
                attribution: .includedInRow,
                cofidDescription: "Potato chips, fine cut, from fast food outlets"
            ),
            CookingFatReconciler.ResolvedItem(
                name: "mixed salad",
                attribution: .additiveCandidate,
                cofidDescription: "Lettuce, raw"
            ),
        ]
        let implicitFats = [
            CookingFatReconciler.ImplicitFat(name: "olive oil dressing", grams: 10)
        ]

        let result = CookingFatReconciler.reconcile(items: items, implicitFats: implicitFats)

        #expect(result.keptImplicitFats.count == 1)
        #expect(result.droppedImplicitFats.isEmpty)
    }
}
