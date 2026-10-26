import CoachLLM
import Testing
@testable import HealthKitIngest

struct SpokenDrinkLogTests {
    @Test("one pint of lager stays one alcoholic pint")
    func onePintOfLager() {
        let payload = FoodLogPayload(
            schemaVersion: "food_log.v1",
            reply: "Logged it.",
            action: .log,
            description: "Alcohol-free lager",
            caloriesKcal: 80,
            items: [
                MealDecompositionPayload.Item(
                    name: "Lager, alcohol-free",
                    estimatedGrams: 1136,
                    confidence: .medium
                )
            ]
        )
        let corrected = SpokenDrinkLog.corrected(payload, spoken: "one pint of lager")
        #expect(corrected.description == "Beer (pint)")
        #expect(corrected.caloriesKcal == 210)
        #expect(corrected.items == nil)
    }

    @Test("I had a lager stays one alcoholic pint")
    func hadALagerStaysOnePint() {
        let corrected = SpokenDrinkLog.corrected(alcoholFreeLagerPayload(), spoken: "I had a lager")
        #expect(corrected.description == "Beer (pint)")
        #expect(corrected.caloriesKcal == 210)
        #expect(corrected.proteinG == 2)
        #expect(corrected.carbsG == 17)
        #expect(corrected.fatG == 0)
        #expect(corrected.items == nil)
    }

    @Test("a pint of lager stays one alcoholic pint")
    func aPintOfLagerStaysOnePint() {
        let corrected = SpokenDrinkLog.corrected(alcoholFreeLagerPayload(), spoken: "a pint of lager")
        #expect(corrected.description == "Beer (pint)")
        #expect(corrected.caloriesKcal == 210)
        #expect(corrected.items == nil)
    }

    @Test("two pints and 2 pints count as two")
    func twoPintsCountAsTwo() {
        for spoken in ["two pints of lager", "2 pints of lager"] {
            let corrected = SpokenDrinkLog.corrected(alcoholFreeLagerPayload(), spoken: spoken)
            #expect(corrected.description == "2 × Beer (pint)")
            #expect(corrected.caloriesKcal == 420)
            #expect(corrected.items == nil)
        }
    }

    @Test("burger and a pint of lager keeps the burger")
    func burgerAndPintOfLagerKeepsTheBurger() {
        let burger = MealDecompositionPayload.Item(
            name: "Beef burger",
            estimatedGrams: 220,
            confidence: .medium
        )
        let burgerKcal = 540.0
        let payload = FoodLogPayload(
            schemaVersion: "food_log.v1",
            reply: "Logged it.",
            action: .log,
            description: "Burger and alcohol-free lager",
            caloriesKcal: burgerKcal,
            proteinG: 32,
            carbsG: 48,
            fatG: 22,
            items: [
                burger,
                MealDecompositionPayload.Item(
                    name: "Lager, alcohol-free",
                    estimatedGrams: 1136,
                    confidence: .low
                )
            ]
        )
        let corrected = SpokenDrinkLog.corrected(payload, spoken: "burger and a pint of lager")
        #expect(corrected.description == "Burger and alcohol-free lager")
        #expect(corrected.description != "Beer (pint)")
        #expect(corrected.items?.map(\.name) == ["Beef burger", "Beer (pint)"])
        #expect(corrected.items?.first == burger)
        #expect(corrected.caloriesKcal == burgerKcal)
        #expect(corrected.proteinG == 32)
        #expect(corrected.carbsG == 48)
        #expect(corrected.fatG == 22)
    }

    @Test("mixed description without items keeps the other food")
    func mixedDescriptionWithoutItemsKeepsOtherFood() {
        let payload = FoodLogPayload(
            schemaVersion: "food_log.v1",
            reply: "Logged it.",
            action: .log,
            description: "Burger and alcohol-free lager",
            caloriesKcal: 800,
            proteinG: 40,
            carbsG: 55,
            fatG: 28
        )
        let corrected = SpokenDrinkLog.corrected(payload, spoken: "burger and a pint of lager")
        #expect(corrected.description == "Burger and Beer (pint)")
        #expect(corrected.caloriesKcal == 800)
        #expect(corrected.proteinG == 40)
        #expect(corrected.carbsG == 55)
        #expect(corrected.fatG == 28)
        #expect(corrected.items == nil)
    }

    @Test("a meal that does not already name the drink gains one pint")
    func mealWithoutDrinkMentionGainsPint() {
        let payload = FoodLogPayload(
            schemaVersion: "food_log.v1",
            reply: "Logged it.",
            action: .log,
            description: "Cheeseburger",
            caloriesKcal: 700,
            proteinG: 40,
            carbsG: 50,
            fatG: 32
        )
        let corrected = SpokenDrinkLog.corrected(payload, spoken: "cheeseburger and a pint of lager")
        #expect(corrected.description == "Cheeseburger")
        #expect(corrected.caloriesKcal == 910)
        #expect(corrected.proteinG == 42)
        #expect(corrected.carbsG == 67)
        #expect(corrected.fatG == 32)
        #expect(corrected.items == nil)
    }

    @Test("spoken alcohol-free lager is not forced to beer")
    func spokenAlcoholFreeIsNotForced() {
        let payload = alcoholFreeLagerPayload()
        let corrected = SpokenDrinkLog.corrected(payload, spoken: "an alcohol-free lager")
        #expect(corrected == payload)
    }

    @Test("beer mention without a drink phrase leaves the meal")
    func beerMentionWithoutDrinkPhraseLeavesMeal() {
        let payload = FoodLogPayload(
            schemaVersion: "food_log.v1",
            reply: "Logged it.",
            action: .log,
            description: "Beef burger",
            caloriesKcal: 540,
            items: [
                MealDecompositionPayload.Item(
                    name: "Beef burger",
                    estimatedGrams: 220,
                    confidence: .medium
                )
            ]
        )
        let corrected = SpokenDrinkLog.corrected(
            payload,
            spoken: "After the beer festival I had a burger"
        )
        #expect(corrected == payload)
    }

    private func alcoholFreeLagerPayload() -> FoodLogPayload {
        FoodLogPayload(
            schemaVersion: "food_log.v1",
            reply: "Logged it.",
            action: .log,
            description: "Alcohol-free lager",
            caloriesKcal: 80,
            proteinG: 0,
            carbsG: 12,
            fatG: 0,
            items: [
                MealDecompositionPayload.Item(
                    name: "Lager, alcohol-free",
                    estimatedGrams: 1136,
                    confidence: .medium
                )
            ]
        )
    }
}
