import CoachLLM
import Foundation
import Testing
@testable import HealthKitIngest

@Suite("Meal HealthKit writer")
struct MealHealthKitWriterTests {
    @Test("own-bundle meals are filtered from ingest")
    func ownWritesFiltered() async throws {
        let mock = MockHealthKitStoreClient()
        let writer = MealHealthKitWriter(store: mock)
        let loggedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let saved = try await writer.saveMeal(
            MealWriteRequest(
                mealID: "meal-1",
                name: "Chicken bowl",
                loggedAt: loggedAt,
                caloriesKcal: 650,
                proteinG: 45,
                carbsG: 70,
                fatG: 18
            )
        )

        #expect(
            MealHealthKitWriter.shouldReIngest(
                savedMeal: saved,
                ownBundleID: HealthKitIngest.defaultOwnBundleID
            ) == false
        )
        #expect(
            IngestSampleFilter.shouldIngest(
                sourceBundleID: saved.energy.sourceBundleID,
                ownBundleID: HealthKitIngest.defaultOwnBundleID
            ) == false
        )
    }
}
