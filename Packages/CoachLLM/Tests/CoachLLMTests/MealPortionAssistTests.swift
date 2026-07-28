import Core
import Foundation
import NutritionKit
import Testing
@testable import CoachLLM

@Suite("Meal portion assist")
struct MealPortionAssistTests {
    @Test("augmented user notes include LiDAR context")
    func augmentedNotes() {
        let assist = MealPortionAssistContext(
            gramScaleFactor: 1.1,
            medianDepthMeters: 0.29,
            referenceDepthMeters: 0.32
        )
        let notes = MealPortionAssist.augmentedUserNotes(base: "No rice", assist: assist)
        #expect(notes?.contains("No rice") == true)
        #expect(notes?.contains("LiDAR depth assist") == true)
    }

    @Test("scaled decomposition multiplies grams")
    func scaledDecomposition() {
        let decomposition = MealDecomposition(
            payload: MealDecompositionPayload(
                schemaVersion: CoachOutputSchemaVersion.mealDecompositionV1.rawValue,
                mealDescription: "Test meal",
                items: [
                    .init(name: "chicken", estimatedGrams: 100, confidence: .high)
                ],
                implicitFats: [
                    .init(name: "oil", estimatedGrams: 10, confidence: .low)
                ],
                portionNotes: nil
            )
        )

        let scaled = MealPortionAssist.scaledDecomposition(decomposition, scaleFactor: 1.2)
        #expect(scaled.items[0].estimatedGrams == 120)
        #expect(scaled.implicitFats[0].estimatedGrams == 12)
    }

    @Test("LiDAR assist increases grounded calories")
    func groundedPipelineWithAssist() async throws {
        final class NotesCapture: @unchecked Sendable {
            var lastNotes: String?
        }
        let capture = NotesCapture()

        struct FixtureVision: MealMacroVisionProviding {
            let capture: NotesCapture

            func decompose(imageJPEGData: Data, userNotes: String?) async throws -> MealDecomposition {
                _ = imageJPEGData
                capture.lastNotes = userNotes
                return MealDecomposition(
                    payload: MealDecompositionPayload(
                        schemaVersion: CoachOutputSchemaVersion.mealDecompositionV1.rawValue,
                        mealDescription: "Chicken rice bowl",
                        items: [
                            .init(name: "grilled chicken breast", estimatedGrams: 100, confidence: .high)
                        ],
                        implicitFats: [],
                        portionNotes: nil
                    )
                )
            }

            func estimateMacrosDirect(imageJPEGData: Data, userNotes: String?) async throws -> MealEstimate {
                MealEstimate(
                    description: "direct",
                    caloriesKcal: 500,
                    proteinG: 40,
                    carbsG: 20,
                    fatG: 10,
                    confidence: .medium
                )
            }
        }

        let assist = MealPortionAssistContext(
            gramScaleFactor: 1.2,
            medianDepthMeters: 0.27,
            referenceDepthMeters: 0.32
        )
        let vision = FixtureVision(capture: capture)
        let baseline = try await GroundedPhotoMacroEstimator(vision: vision)
            .estimateMacros(imageJPEGData: Data([0xFF, 0xD8, 0xFF]), userNotes: nil, portionAssist: nil, progress: nil)
        let assisted = try await GroundedPhotoMacroEstimator(vision: vision)
            .estimateMacros(imageJPEGData: Data([0xFF, 0xD8, 0xFF]), userNotes: nil, portionAssist: assist, progress: nil)

        #expect(capture.lastNotes?.contains("LiDAR depth assist") == true)
        #expect(assisted.caloriesKcal > baseline.caloriesKcal)
        #expect(assisted.groundingWarnings.first?.contains("LiDAR depth assist") == true)
    }
}
