import Core
import Diagnostics
import Foundation
import OSLog

private let photoMealPersistLog = Logger(subsystem: "com.cameronro.helm", category: "NutritionKit")

/// HealthKit + GRDB persist for a confirmed photo estimate.
public struct PhotoMealPersister: Sendable {
    private let writer: any MealHealthKitWriting
    private let localStore: PhotoMealLocalStore?

    public init(
        writer: any MealHealthKitWriting = MealHealthKitWriter(),
        localStore: PhotoMealLocalStore? = nil
    ) {
        self.writer = writer
        self.localStore = localStore
    }

    public func confirm(
        estimate: MealEstimate,
        name: String,
        bucket: MealBucket = .snacks,
        loggedAt: Date = Date(),
        helmDay: HelmDay? = nil,
        mealID: String = UUID().uuidString
    ) async throws -> SavedMealSamples {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? estimate.description : trimmedName
        let request = MealWriteRequest(
            mealID: mealID,
            name: resolvedName,
            loggedAt: loggedAt,
            helmDay: helmDay,
            caloriesKcal: estimate.caloriesKcal,
            proteinG: estimate.proteinG,
            carbsG: estimate.carbsG,
            fatG: estimate.fatG,
            lineItems: estimate.lineItems,
            mealSource: HelmHealthKitMetadata.mealSourcePhoto
        )

        do {
            let saved = try await writer.saveMeal(request)
            try localStore?.recordSavedMeal(request, saved: saved, bucket: bucket)
            photoMealPersistLog.debug("Photo meal saved mealID=\(saved.mealID, privacy: .public)")
            return saved
        } catch {
            photoMealPersistLog.error(
                "Photo meal write failed: \(String(describing: type(of: error)), privacy: .public)"
            )
            Task {
                await DiagnosticsLog.shared.capture(
                    error: error,
                    category: .nutritionKit,
                    message: "Photo meal HealthKit write failed"
                )
            }
            throw error
        }
    }
}
