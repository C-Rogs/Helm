import Core
import Foundation
import NutritionKit

public struct PhotoMacroEstimator: Sendable, MealMacroEstimating {
    private let grounded: GroundedPhotoMacroEstimator
    private let visionDirect: VisionDirectPhotoMacroEstimator
    private let preferences: any PhotoCofidGroundingPreferences

    public init(
        router: MealVisionRouter,
        lookup: NutritionLookup = .shared,
        preferences: any PhotoCofidGroundingPreferences = DefaultPhotoCofidGroundingPreferences()
    ) {
        grounded = GroundedPhotoMacroEstimator(vision: router, lookup: lookup)
        visionDirect = VisionDirectPhotoMacroEstimator(vision: router)
        self.preferences = preferences
    }

    public init(
        grounded: GroundedPhotoMacroEstimator,
        visionDirect: VisionDirectPhotoMacroEstimator,
        preferences: any PhotoCofidGroundingPreferences = DefaultPhotoCofidGroundingPreferences()
    ) {
        self.grounded = grounded
        self.visionDirect = visionDirect
        self.preferences = preferences
    }

    @available(*, deprecated, message: "Use PhotoMacroEstimator(router:) for grounded photo macros.")
    public init(provider: GeminiProvider) {
        let keyStore = APIKeyStore()
        let router = MealVisionRouter(
            apiKeyStore: keyStore,
            geminiVision: GeminiMealVisionProvider(apiKeyStore: keyStore)
        )
        grounded = GroundedPhotoMacroEstimator(vision: router)
        visionDirect = VisionDirectPhotoMacroEstimator(vision: router)
        preferences = DefaultPhotoCofidGroundingPreferences()
        _ = provider
    }

    public func estimateMacros(
        imageJPEGData: Data,
        userNotes: String?,
        portionAssist: MealPortionAssistContext? = nil,
        progress: MealMacroEstimateProgress? = nil
    ) async throws -> MealEstimate {
        if preferences.isPhotoCofidGroundingEnabled() {
            return try await grounded.estimateMacros(
                imageJPEGData: imageJPEGData,
                userNotes: userNotes,
                portionAssist: portionAssist,
                progress: progress
            )
        }
        return try await visionDirect.estimateMacros(
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
        guard !preferences.isPhotoCofidGroundingEnabled() else {
            throw CoachProviderError.requestFailed("Refinement is only available in simple photo scan mode.")
        }
        return try await visionDirect.refineMacros(
            imageJPEGData: imageJPEGData,
            priorEstimate: priorEstimate,
            userCorrections: userCorrections,
            userNotes: userNotes,
            portionAssist: portionAssist,
            progress: progress
        )
    }
}
