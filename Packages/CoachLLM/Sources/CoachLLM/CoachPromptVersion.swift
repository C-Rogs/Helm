public enum CoachPromptVersion: String, Sendable, Equatable, CaseIterable {
    case chatV1 = "chat.prompt.v1"
    case sessionAdjustmentV1 = "session_adjustment.prompt.v1"
    case mealEstimateV1 = "meal_estimate.prompt.v1"
    case mealDecompositionV1 = "meal_decomposition.prompt.v1"
    case briefV1 = "brief.prompt.v1"
}
