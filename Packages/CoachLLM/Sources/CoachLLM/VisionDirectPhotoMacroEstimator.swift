import Core
import Foundation

public struct VisionDirectPhotoMacroEstimator: Sendable {
    private let vision: any MealMacroVisionProviding

    public init(vision: any MealMacroVisionProviding) {
        self.vision = vision
    }

    public func estimateMacros(
        imageJPEGData: Data,
        userNotes: String?,
        portionAssist: MealPortionAssistContext? = nil,
        progress: MealMacroEstimateProgress? = nil
    ) async throws -> MealEstimate {
        let visionNotes = MealPortionAssist.augmentedUserNotes(base: userNotes, assist: portionAssist)
        if portionAssist != nil {
            progress?("Applying LiDAR depth to portion scale…")
        }
        progress?("Analysing portions and ingredients…")
        let draft = try await vision.draftMeal(imageJPEGData: imageJPEGData, userNotes: visionNotes)
        let scaledDraft = portionAssist.map {
            MealPortionAssist.scaledDraft(draft, scaleFactor: $0.gramScaleFactor)
        } ?? draft
        progress?("Building draft…")
        let lidarWarning = portionAssist.map { MealPortionAssist.lidarWarning(for: $0) }
        return MealVisionDraftMapping.mealEstimate(
            from: scaledDraft,
            requiresRefinement: true,
            portionAssistWarning: lidarWarning
        )
    }

    public func refineMacros(
        imageJPEGData: Data,
        priorEstimate: MealEstimate,
        userCorrections: String,
        userNotes: String?,
        portionAssist: MealPortionAssistContext? = nil,
        progress: MealMacroEstimateProgress? = nil
    ) async throws -> MealEstimate {
        guard let priorDraft = MealVisionDraftMapping.draft(from: priorEstimate) else {
            throw CoachProviderError.requestFailed("No draft ingredients to refine.")
        }
        let visionNotes = MealPortionAssist.augmentedUserNotes(base: userNotes, assist: portionAssist)
        progress?("Applying your corrections…")
        let refined = try await vision.refineDraft(
            imageJPEGData: imageJPEGData,
            priorDraft: priorDraft,
            userCorrections: userCorrections,
            userNotes: visionNotes
        )
        let scaledDraft = portionAssist.map {
            MealPortionAssist.scaledDraft(refined, scaleFactor: $0.gramScaleFactor)
        } ?? refined
        progress?("Finalising estimate…")
        let lidarWarning = portionAssist.map { MealPortionAssist.lidarWarning(for: $0) }
        return MealVisionDraftMapping.mealEstimate(
            from: scaledDraft,
            requiresRefinement: false,
            portionAssistWarning: lidarWarning
        )
    }
}

extension VisionDirectPhotoMacroEstimator: MealMacroEstimating {}
