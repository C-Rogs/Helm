import CoachLLM
import Core
import Foundation
import Testing

struct EnabledPhotoCofidGroundingPreferences: PhotoCofidGroundingPreferences {
    func isPhotoCofidGroundingEnabled() -> Bool { true }
}

struct DisabledPhotoCofidGroundingPreferences: PhotoCofidGroundingPreferences {
    func isPhotoCofidGroundingEnabled() -> Bool { false }
}

@Suite("Vision direct photo macro pipeline")
struct VisionDirectPhotoMacroEstimatorTests {
    private final class DraftFixtureVision: MealMacroVisionProviding, @unchecked Sendable {
        var refinedName: String?

        func decompose(imageJPEGData: Data, userNotes: String?) async throws -> MealDecomposition {
            throw CoachProviderError.cancelled
        }

        func estimateMacrosDirect(imageJPEGData: Data, userNotes: String?) async throws -> MealEstimate {
            throw CoachProviderError.cancelled
        }

        func draftMeal(imageJPEGData: Data, userNotes: String?) async throws -> MealVisionDraft {
            _ = imageJPEGData
            _ = userNotes
            return MealVisionDraft(
                mealDescription: "Salmon plate",
                items: [
                    .init(
                        name: "Salmon, thick slices",
                        estimatedGrams: 120,
                        caloriesKcal: 248,
                        proteinG: 25,
                        carbsG: 0,
                        fatG: 16,
                        portionMeta: "4 thick slices (~10mm), not thin sashimi",
                        confidence: .medium
                    )
                ],
                portionNotes: "Half plate coverage"
            )
        }

        func refineDraft(
            imageJPEGData: Data,
            priorDraft: MealVisionDraft,
            userCorrections: String,
            userNotes: String?
        ) async throws -> MealVisionDraft {
            _ = imageJPEGData
            _ = userNotes
            refinedName = userCorrections
            return MealVisionDraft(
                mealDescription: priorDraft.mealDescription,
                items: priorDraft.items.map { item in
                    MealVisionDraftPayload.Item(
                        name: item.name,
                        estimatedGrams: item.estimatedGrams + 10,
                        caloriesKcal: item.caloriesKcal + 20,
                        proteinG: item.proteinG + 2,
                        carbsG: item.carbsG,
                        fatG: item.fatG + 1,
                        portionMeta: item.portionMeta + " · corrected",
                        confidence: item.confidence
                    )
                },
                portionNotes: priorDraft.portionNotes
            )
        }
    }

    @Test("draft maps portion meta and requires refinement")
    func draftMapping() async throws {
        let estimate = try await VisionDirectPhotoMacroEstimator(vision: DraftFixtureVision())
            .estimateMacros(imageJPEGData: Data([0xFF, 0xD8, 0xFF]), userNotes: nil, progress: nil)

        #expect(estimate.description == "Salmon plate")
        #expect(estimate.scanMode == .visionDirect)
        #expect(estimate.requiresRefinement)
        #expect(estimate.lineItems.count == 1)
        #expect(estimate.lineItems[0].portionMeta?.contains("thick") == true)
        #expect(estimate.caloriesKcal == 248)
    }

    @Test("LiDAR scales grams and macros together")
    func lidarScalesDraft() async throws {
        let assist = MealPortionAssistContext(
            gramScaleFactor: 1.5,
            medianDepthMeters: 0.27,
            referenceDepthMeters: 0.32
        )
        let estimate = try await VisionDirectPhotoMacroEstimator(vision: DraftFixtureVision())
            .estimateMacros(
                imageJPEGData: Data([0xFF, 0xD8, 0xFF]),
                userNotes: nil,
                portionAssist: assist,
                progress: nil
            )

        #expect(estimate.lineItems[0].grams == 180)
        #expect(estimate.caloriesKcal == 372)
    }

    @Test("refine clears requiresRefinement")
    func refineDraft() async throws {
        let vision = DraftFixtureVision()
        let estimator = VisionDirectPhotoMacroEstimator(vision: vision)
        let draft = try await estimator.estimateMacros(
            imageJPEGData: Data([0xFF, 0xD8, 0xFF]),
            userNotes: nil,
            progress: nil
        )

        let refined = try await estimator.refineMacros(
            imageJPEGData: Data([0xFF, 0xD8, 0xFF]),
            priorEstimate: draft,
            userCorrections: "thicker salmon",
            userNotes: nil,
            progress: nil
        )

        #expect(refined.requiresRefinement == false)
        #expect(refined.lineItems[0].grams == 130)
        #expect(vision.refinedName == "thicker salmon")
    }

    @Test("photo macro estimator routes by preference")
    func estimatorRouting() async throws {
        let vision = DraftFixtureVision()
        let grounded = GroundedPhotoMacroEstimator(vision: vision)
        let direct = VisionDirectPhotoMacroEstimator(vision: vision)

        let enabled = PhotoMacroEstimator(
            grounded: grounded,
            visionDirect: direct,
            preferences: EnabledPhotoCofidGroundingPreferences()
        )
        let disabled = PhotoMacroEstimator(
            grounded: grounded,
            visionDirect: direct,
            preferences: DisabledPhotoCofidGroundingPreferences()
        )

        let directEstimate = try await disabled.estimateMacros(
            imageJPEGData: Data([0xFF, 0xD8, 0xFF]),
            userNotes: nil,
            progress: nil
        )
        #expect(directEstimate.scanMode == .visionDirect)

        await #expect(throws: (any Error).self) {
            try await enabled.estimateMacros(
                imageJPEGData: Data([0xFF, 0xD8, 0xFF]),
                userNotes: nil,
                progress: nil
            )
        }
    }
}
