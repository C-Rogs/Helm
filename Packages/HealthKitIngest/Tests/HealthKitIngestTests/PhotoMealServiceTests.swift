import CoachLLM
import Core
import Foundation
import Persistence
import Testing
@testable import HealthKitIngest

private let testCalendar = Calendar(identifier: .gregorian)

private struct StubMealMacroEstimator: MealMacroEstimating {
    let estimate: MealEstimate

    func estimateMacros(
        imageJPEGData: Data,
        userNotes: String?,
        progress: MealMacroEstimateProgress?
    ) async throws -> MealEstimate {
        _ = imageJPEGData
        _ = userNotes
        _ = progress
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
        let store = try PersistenceStore.inMemory()
        let service = PhotoMealService(
            estimator: StubMealMacroEstimator(estimate: estimate),
            writer: MealHealthKitWriter(store: MockHealthKitStoreClient()),
            localStore: PhotoMealLocalStore(store: store)
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
            bucket: .lunch,
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

        let loggedDay = HelmDay.day(for: Date(timeIntervalSince1970: 1_700_000_000), calendar: testCalendar)
        let nutritionDay = try store.nutrition.fetchDay(helmDay: loggedDay)
        #expect(nutritionDay?.totalEnergy?.kilocalories == 700)
        let meals = try store.nutrition.fetchMeals(for: loggedDay)
        #expect(meals.count == 1)
        #expect(meals[0].source == .photo)
        #expect(meals[0].name == "Large chicken bowl")
        #expect(meals[0].bucket == .lunch)
    }
}
