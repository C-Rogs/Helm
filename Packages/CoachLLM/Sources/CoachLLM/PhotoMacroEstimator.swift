import Core
import Foundation
import NutritionKit

/// Photo meal macros via vision-direct only. CoFID grounding is for offline search / describe, not photos.
public struct PhotoMacroEstimator: Sendable, MealMacroEstimating {
    private let visionDirect: VisionDirectPhotoMacroEstimator

    public init(router: MealVisionRouter) {
        visionDirect = VisionDirectPhotoMacroEstimator(vision: router)
    }

    public init(visionDirect: VisionDirectPhotoMacroEstimator) {
        self.visionDirect = visionDirect
    }

    @available(*, deprecated, message: "Use PhotoMacroEstimator(router:) for vision-direct photo macros.")
    public init(provider: GeminiProvider) {
        let keyStore = APIKeyStore()
        let router = MealVisionRouter(
            apiKeyStore: keyStore,
            geminiVision: GeminiMealVisionProvider(apiKeyStore: keyStore)
        )
        visionDirect = VisionDirectPhotoMacroEstimator(vision: router)
        _ = provider
    }

    public func estimateMacros(
        imageJPEGData: Data,
        userNotes: String?,
        portionAssist: MealPortionAssistContext? = nil,
        progress: MealMacroEstimateProgress? = nil
    ) async throws -> MealEstimate {
        try await visionDirect.estimateMacros(
            imageJPEGData: imageJPEGData,
            userNotes: userNotes,
            portionAssist: portionAssist,
            progress: progress
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
        try await visionDirect.refineMacros(
            imageJPEGData: imageJPEGData,
            priorEstimate: priorEstimate,
            userCorrections: userCorrections,
            userNotes: userNotes,
            portionAssist: portionAssist,
            progress: progress
        )
    }
}
