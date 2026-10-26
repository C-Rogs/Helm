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
}
