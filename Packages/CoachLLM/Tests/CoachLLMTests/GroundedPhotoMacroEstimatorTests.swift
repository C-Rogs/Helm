import CoachLLM
import Core
import Foundation
import NutritionKit
import Testing

@Suite("Grounded photo macro pipeline")
struct GroundedPhotoMacroEstimatorTests {
    private struct FixtureVision: MealVisionProviding {
        func decompose(imageJPEGData: Data) async throws -> MealDecomposition {
            _ = imageJPEGData
            let payload = MealDecompositionPayload(
                schemaVersion: CoachOutputSchemaVersion.mealDecompositionV1.rawValue,
                mealDescription: "Chicken rice bowl",
                items: [
                    .init(name: "grilled chicken breast", estimatedGrams: 140, confidence: .high),
                    .init(name: "white rice cooked", estimatedGrams: 180, confidence: .medium)
                ],
                implicitFats: [
                    .init(name: "cooking oil", estimatedGrams: 8, confidence: .low)
                ],
                portionNotes: "Half standard dinner plate"
            )
            return MealDecomposition(payload: payload)
        }
    }

    @Test("fixture decomposition aggregates grounded totals with line items")
    func groundedPipeline() async throws {
        let estimator = GroundedPhotoMacroEstimator(vision: FixtureVision())
        let estimate = try await estimator.estimateMacros(imageJPEGData: Data([0xFF, 0xD8, 0xFF]))

        #expect(estimate.description == "Chicken rice bowl")
        #expect(estimate.lineItems.count == 3)
        #expect(estimate.caloriesKcal > 400)
        #expect(estimate.caloriesKcal < 900)
        #expect(estimate.proteinG > 30)
        #expect(estimate.confidence == .low)
    }

    @Test("gemini vision fixture decodes decomposition")
    func geminiVisionFixture() async throws {
        let store = APIKeyStore(service: "com.cameronro.helm.tests.\(UUID().uuidString)")
        try store.save("fixture-key", kind: .gemini)
        let vision = GeminiMealVisionProvider(
            apiKeyStore: store,
            httpClient: FixtureGeminiHTTPClient(bundle: .module)
        )

        let decomposition = try await vision.decompose(imageJPEGData: Data([0xFF, 0xD8, 0xFF]))
        #expect(decomposition.mealDescription == "Chicken rice bowl")
        #expect(decomposition.items.count == 2)
        #expect(decomposition.implicitFats.count == 1)
    }

    @Test("openrouter vision fixture decodes decomposition")
    func openRouterVisionFixture() async throws {
        let store = APIKeyStore(service: "com.cameronro.helm.tests.\(UUID().uuidString)")
        try store.save("fixture-key", kind: .openRouter)
        let vision = OpenRouterMealVisionProvider(
            apiKeyStore: store,
            httpClient: FixtureOpenRouterHTTPClient(bundle: .module)
        )

        let decomposition = try await vision.decompose(imageJPEGData: Data([0xFF, 0xD8, 0xFF]))
        #expect(decomposition.mealDescription == "Chicken rice bowl")
        #expect(decomposition.items.count == 2)
    }

    @Test("router falls back to gemini when openrouter fails")
    func routerFallsBackToGemini() async throws {
        struct FailingOpenRouter: MealVisionProviding {
            func decompose(imageJPEGData: Data) async throws -> MealDecomposition {
                throw CoachProviderError.requestFailed("OpenRouter request failed with status 404.")
            }
        }

        let store = APIKeyStore(service: "com.cameronro.helm.tests.\(UUID().uuidString)")
        try store.save("gemini-key", kind: .gemini)
        try store.save("openrouter-key", kind: .openRouter)

        let router = MealVisionRouter(
            apiKeyStore: store,
            geminiVision: GeminiMealVisionProvider(
                apiKeyStore: store,
                httpClient: FixtureGeminiHTTPClient(bundle: .module)
            ),
            openRouterVision: FailingOpenRouter()
        )

        let estimate = try await PhotoMacroEstimator(router: router).estimateMacros(
            imageJPEGData: Data([0xFF, 0xD8, 0xFF])
        )
        #expect(estimate.lineItems.count == 3)
    }
}
