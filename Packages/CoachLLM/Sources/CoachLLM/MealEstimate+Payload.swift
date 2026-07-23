import Core
import Foundation

extension MealEstimate {
    public init(payload: MealEstimatePayload) {
        self.init(
            description: payload.description,
            caloriesKcal: payload.caloriesKcal,
            proteinG: payload.proteinG,
            carbsG: payload.carbsG,
            fatG: payload.fatG,
            confidence: MealEstimate.Confidence(rawValue: payload.confidence.rawValue) ?? .medium
        )
    }
}
