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

    func refineMacros(
        imageJPEGData: Data,
        priorEstimate: MealEstimate,
        userCorrections: String,
        userNotes: String?,
        portionAssist: MealPortionAssistContext?,
        progress: MealMacroEstimateProgress?
    ) async throws -> MealEstimate
}

extension MealMacroEstimating {
    public func refineMacros(
        imageJPEGData: Data,
        priorEstimate: MealEstimate,
        userCorrections: String,
        userNotes: String?,
        portionAssist: MealPortionAssistContext?,
        progress: MealMacroEstimateProgress?
    ) async throws -> MealEstimate {
        throw CoachProviderError.requestFailed("Refinement is not supported for this estimator.")
    }
}
