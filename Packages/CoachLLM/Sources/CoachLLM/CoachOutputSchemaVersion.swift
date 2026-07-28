public enum CoachOutputSchemaVersion: String, Sendable, Codable, Equatable, CaseIterable {
    case chatV1 = "chat.v1"
    case sessionAdjustmentV1 = "session_adjustment.v1"
    case sessionAdjustmentV2 = "session_adjustment.v2"
    case mealEstimateV1 = "meal_estimate.v1"
    case mealDecompositionV1 = "meal_decomposition.v1"
    case settingsAdjustmentV1 = "settings_adjustment.v1"
    case workoutStartV1 = "workout_start.v1"
    case briefV1 = "brief.v1"
}
