import CoachLLM
import Core
import Foundation
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("Food log proposal validator")
struct FoodLogProposalValidatorTests {
    private let day = HelmDay(year: 2026, month: 9, day: 7)
    private let mealID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    private func makeStore() throws -> PersistenceStore {
        let store = try PersistenceStore.inMemory()
        try store.nutrition.upsertMeal(
            MealRecord(
                id: mealID,
                helmDay: day,
                name: "Dinner",
                loggedAt: Date(),
                bucket: .dinner,
                energy: Energy(kilocalories: 500),
                proteinGrams: 40,
                carbohydrateGrams: 30,
                fatGrams: 20,
                source: .quickAdd
            )
        )
        return store
    }

    @Test("log proposals always validate")
    func logAlwaysValid() throws {
        let store = try makeStore()
        let payload = FoodLogPayload(
            schemaVersion: "food_log.v1",
            reply: "Logged.",
            action: .log,
            bucket: "dinner",
            caloriesKcal: 200
        )
        #expect(
            FoodLogProposalValidator.validate(
                payload: payload,
                queryContext: nil,
                persistence: store
            ) == nil
        )
    }

    @Test("edit requires meal query and meal id")
    func editRequiresMealQueryAndID() throws {
        let store = try makeStore()
        let payload = FoodLogPayload(
            schemaVersion: "food_log.v1",
            reply: "Updating.",
            action: .edit,
            mealID: mealID.uuidString,
            bucket: "dinner",
            caloriesKcal: 200
        )
        #expect(
            FoodLogProposalValidator.validate(
                payload: payload,
                queryContext: nil,
                persistence: store
            ) == .missingMealQuery
        )
    }

    @Test("edit accepts fresh meal query context")
    func editAcceptsFreshQuery() throws {
        let store = try makeStore()
        let payload = FoodLogPayload(
            schemaVersion: "food_log.v1",
            reply: "Updating.",
            action: .edit,
            mealID: mealID.uuidString,
            bucket: "dinner",
            caloriesKcal: 200
        )
        let context = MealQueryContext(
            helmDay: day,
            bucket: .dinner,
            mealIDs: [mealID]
        )
        #expect(
            FoodLogProposalValidator.validate(
                payload: payload,
                queryContext: context,
                persistence: store
            ) == nil
        )
    }
}
