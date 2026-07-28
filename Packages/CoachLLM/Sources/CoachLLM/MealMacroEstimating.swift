import Core
import Foundation

public typealias MealMacroEstimateProgress = @Sendable (String) -> Void

public protocol MealMacroEstimating: Sendable {
    func estimateMacros(
        imageJPEGData: Data,
        userNotes: String?,
        portionAssist: MealPortionAssistContext?,
        progress: MealMacroEstimateProgress?
    ) async throws -> MealEstimate
}
