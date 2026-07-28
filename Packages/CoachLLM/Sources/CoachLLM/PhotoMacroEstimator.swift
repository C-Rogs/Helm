import Core
import Foundation
import NutritionKit

public struct PhotoMacroEstimator: Sendable, MealMacroEstimating {
    private let grounded: GroundedPhotoMacroEstimator

    public init(router: MealVisionRouter, lookup: NutritionLookup = NutritionLookup()) {
        grounded = GroundedPhotoMacroEstimator(vision: router, lookup: lookup)
    }

    public init(grounded: GroundedPhotoMacroEstimator) {
        self.grounded = grounded
    }

    @available(*, deprecated, message: "Use PhotoMacroEstimator(router:) for grounded photo macros.")
    public init(provider: GeminiProvider) {
        let keyStore = APIKeyStore()
        let router = MealVisionRouter(
            apiKeyStore: keyStore,
            geminiVision: GeminiMealVisionProvider(apiKeyStore: keyStore)
        )
        grounded = GroundedPhotoMacroEstimator(vision: router)
        _ = provider
    }

    public func estimateMacros(
        imageJPEGData: Data,
        userNotes: String?,
        progress: MealMacroEstimateProgress? = nil
    ) async throws -> MealEstimate {
        try await grounded.estimateMacros(
            imageJPEGData: imageJPEGData,
            userNotes: userNotes,
            progress: progress
        )
    }
}

