import Core
import Foundation

public protocol MealMacroVisionProviding: MealVisionProviding {
    func estimateMacrosDirect(imageJPEGData: Data, userNotes: String?) async throws -> MealEstimate
    func draftMeal(imageJPEGData: Data, userNotes: String?) async throws -> MealVisionDraft
    func refineDraft(
        imageJPEGData: Data,
        priorDraft: MealVisionDraft,
        userCorrections: String,
        userNotes: String?
    ) async throws -> MealVisionDraft
}

extension MealMacroVisionProviding {
    public func draftMeal(imageJPEGData: Data, userNotes: String?) async throws -> MealVisionDraft {
        _ = imageJPEGData
        _ = userNotes
        throw CoachProviderError.unavailable("Meal vision draft is not available for this provider.")
    }

    public func refineDraft(
        imageJPEGData: Data,
        priorDraft: MealVisionDraft,
        userCorrections: String,
        userNotes: String?
    ) async throws -> MealVisionDraft {
        _ = imageJPEGData
        _ = priorDraft
        _ = userCorrections
        _ = userNotes
        throw CoachProviderError.unavailable("Meal vision draft refinement is not available for this provider.")
    }
}
