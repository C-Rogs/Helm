import Core
import Foundation
import Testing
@testable import HealthKitIngest

private struct StubMealMacroEstimator: MealMacroEstimating {
    let estimate: MealEstimate

    func estimateMacros(imageJPEGData: Data) async throws -> MealEstimate {
        _ = imageJPEGData
        return estimate
    }
}

@Suite("Photo meal service")
struct PhotoMealServiceTests {
    private var fixtureJPEGData: Data {
        Data([0xFF, 0xD8, 0xFF, 0xDB, 0x00, 0x43, 0x00])
    }

    @Test("fixture image decodes to editable estimate and writes without re-ingest")
    func fixtureEstimateAndConfirm() async throws {
        let estimate = MealEstimate(
            description: "Chicken rice bowl",
            caloriesKcal: 650,
            proteinG: 45,
            carbsG: 70,
            fatG: 18,
            confidence: .medium
        )
        let service = PhotoMealService(
            estimator: StubMealMacroEstimator(estimate: estimate),
            writer: MealHealthKitWriter(store: MockHealthKitStoreClient())
        )

        let decoded = try await service.estimate(from: fixtureJPEGData)

        #expect(decoded.description == "Chicken rice bowl")
        #expect(decoded.caloriesKcal == 650)
        #expect(decoded.proteinG == 45)
        #expect(decoded.confidence == .medium)

        var edited = decoded
        edited.caloriesKcal = 700
        edited.description = "Large chicken bowl"

        let saved = try await service.confirm(
            estimate: edited,
            name: edited.description,
            loggedAt: Date(timeIntervalSince1970: 1_700_000_000),
            mealID: "fixture-meal"
        )

        #expect(saved.mealID == "fixture-meal")
        #expect(
            MealHealthKitWriter.shouldReIngest(
                savedMeal: saved,
                ownBundleID: HealthKitIngest.defaultOwnBundleID
            ) == false
        )
    }
}
