import CoachLLM
import Core
import Foundation
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("MealHistoryQuery")
struct MealHistoryQueryTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test("parses meal_query payload")
    func parsesQuery() {
        let text = """
        Looking up.
        {"schemaVersion":"meal_query.v1","queryType":"bucketOnDay","helmDay":"2026-07-29","bucket":"breakfast"}
        """
        let payload = MealQueryPayloadParser.parse(from: text)
        #expect(payload?.queryType == .bucketOnDay)
        #expect(payload?.helmDay == "2026-07-29")
        #expect(payload?.bucket == "breakfast")
    }

    @Test("parses meal_copy payload")
    func parsesCopy() {
        let text = """
        {"schemaVersion":"meal_copy.v1","reply":"Copying Tuesday breakfast.","sourceHelmDay":"2026-07-29","sourceBucket":"breakfast","targetHelmDay":"2026-08-02","targetBucket":"breakfast"}
        """
        let payload = MealCopyPayloadParser.parse(from: text)
        #expect(payload?.sourceHelmDay == "2026-07-29")
        #expect(payload?.targetBucket == "breakfast")
    }

    @Test("bucketOnDay returns macros")
    func bucketOnDayReturnsMacros() async throws {
        let store = try PersistenceStore.inMemory()
        let day = HelmDay(year: 2026, month: 7, day: 29)
        try store.nutrition.upsertMeal(
            MealRecord(
                helmDay: day,
                name: "Oats",
                loggedAt: Date(),
                bucket: .breakfast,
                energy: Energy(kilocalories: 420),
                proteinGrams: 22,
                carbohydrateGrams: 55,
                fatGrams: 10,
                source: .quickAdd
            )
        )

        let service = MealHistoryQueryService(store: store, calendar: calendar)
        let result = try service.run(
            MealQueryPayload(queryType: .bucketOnDay, helmDay: "2026-07-29", bucket: "breakfast")
        )
        #expect(result.contains("Oats"))
        #expect(result.contains("kcal=420"))
        #expect(result.contains("P=22"))
    }
}
