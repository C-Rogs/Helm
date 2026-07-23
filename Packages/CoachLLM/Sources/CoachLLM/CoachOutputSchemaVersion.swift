public enum CoachOutputSchemaVersion: String, Sendable, Codable, Equatable, CaseIterable {
    case chatV1 = "chat.v1"
    case sessionAdjustmentV1 = "session_adjustment.v1"
    case mealEstimateV1 = "meal_estimate.v1"
}
