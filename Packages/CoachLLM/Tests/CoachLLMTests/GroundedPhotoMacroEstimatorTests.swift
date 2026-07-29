import CoachLLM
import Core
import Foundation
import NutritionKit
import Testing

@Suite("Grounded photo macro pipeline")
struct GroundedPhotoMacroEstimatorTests {
    private struct FixtureVision: MealMacroVisionProviding {
        func decompose(imageJPEGData: Data, userNotes: String?) async throws -> MealDecomposition {
            _ = imageJPEGData
            _ = userNotes
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

        func estimateMacrosDirect(imageJPEGData: Data, userNotes: String?) async throws -> MealEstimate {
            _ = imageJPEGData
            _ = userNotes
            return MealEstimate(
                description: "Fixture direct",
                caloriesKcal: 650,
                proteinG: 55,
                carbsG: 40,
                fatG: 25,
                confidence: .medium
            )
        }
    }

    @Test("fixture decomposition aggregates grounded totals with line items")
    func groundedPipeline() async throws {
        let estimator = GroundedPhotoMacroEstimator(vision: FixtureVision())
        let estimate = try await estimator.estimateMacros(imageJPEGData: Data([0xFF, 0xD8, 0xFF]), userNotes: nil, progress: nil)

        #expect(estimate.description == "Chicken rice bowl")
        #expect(estimate.lineItems.count == 3)
        #expect(estimate.caloriesKcal > 400)
        #expect(estimate.caloriesKcal < 900)
        #expect(estimate.proteinG > 30)
        #expect(estimate.confidence == .low)
    }

    @Test("fish and chips drops duplicate cooking oil from implicit fats")
    func fishAndChipsDropsDuplicateOil() async throws {
        struct FishAndChipsVision: MealMacroVisionProviding {
            func decompose(imageJPEGData: Data, userNotes: String?) async throws -> MealDecomposition {
                _ = imageJPEGData
                _ = userNotes
                return MealDecomposition(
                    payload: MealDecompositionPayload(
                        schemaVersion: CoachOutputSchemaVersion.mealDecompositionV1.rawValue,
                        mealDescription: "Fish and chips",
                        items: [
                            .init(name: "battered cod", estimatedGrams: 180, confidence: .medium),
                            .init(name: "Potato chips, fried in commercial oil", estimatedGrams: 220, confidence: .high)
                        ],
                        implicitFats: [
                            .init(name: "cooking oil", estimatedGrams: 12, confidence: .low)
                        ]
                    )
                )
            }

            func estimateMacrosDirect(imageJPEGData: Data, userNotes: String?) async throws -> MealEstimate {
                throw CoachProviderError.cancelled
            }
        }

        let estimate = try await GroundedPhotoMacroEstimator(vision: FishAndChipsVision()).estimateMacros(
            imageJPEGData: Data([0xFF, 0xD8, 0xFF]),
            userNotes: nil,
            progress: nil
        )

        #expect(estimate.lineItems.count == 2)
        #expect(estimate.groundingWarnings.contains {
            $0.contains("Cooking fat already included")
        })
    }

    @Test("gemini vision fixture decodes decomposition")
    func geminiVisionFixture() async throws {
        let store = APIKeyStore(service: "com.cameronro.helm.tests.\(UUID().uuidString)")
        try store.save("fixture-key", kind: .gemini)
        let vision = GeminiMealVisionProvider(
            apiKeyStore: store,
            httpClient: FixtureGeminiHTTPClient(bundle: .module)
        )

        let decomposition = try await vision.decompose(imageJPEGData: Data([0xFF, 0xD8, 0xFF]), userNotes: nil)
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

        let decomposition = try await vision.decompose(imageJPEGData: Data([0xFF, 0xD8, 0xFF]), userNotes: nil)
        #expect(decomposition.mealDescription == "Chicken rice bowl")
        #expect(decomposition.items.count == 2)
    }

    @Test("gemini vision retries alternate model after 404")
    func geminiVisionRetriesAlternateModel() async throws {
        final class CountingGeminiHTTPClient: GeminiHTTPClient, @unchecked Sendable {
            private let lock = NSLock()
            private var attempts: [String] = []

            var lastStreamRequestID: UUID?
            var lastGenerateRequestID: UUID?

            func streamGenerate(_ request: GeminiStreamHTTPRequest) async throws -> AsyncThrowingStream<Data, Error> {
                lastStreamRequestID = request.requestID
                return AsyncThrowingStream { $0.finish() }
            }

            func generateContent(_ request: GeminiGenerateHTTPRequest) async throws -> Data {
                lastGenerateRequestID = request.requestID
                lock.withLock { attempts.append(request.model.rawValue) }
                if request.model == .flashLite {
                    throw CoachProviderError.requestFailed(
                        "Gemini request failed with status 404: models/gemini-3.5-flash-lite is no longer available."
                    )
                }
                guard let url = Bundle.module.url(forResource: "gemini_generate_meal_decomposition", withExtension: "json") else {
                    throw CoachProviderError.requestFailed("Missing fixture")
                }
                return try Data(contentsOf: url)
            }

            func recordedAttempts() -> [String] {
                lock.withLock { attempts }
            }
        }

        let store = APIKeyStore(service: "com.cameronro.helm.tests.\(UUID().uuidString)")
        try store.save("fixture-key", kind: .gemini)
        let httpClient = CountingGeminiHTTPClient()
        let vision = GeminiMealVisionProvider(
            apiKeyStore: store,
            httpClient: httpClient,
            models: [.flashLite, .flash]
        )

        let decomposition = try await vision.decompose(imageJPEGData: Data([0xFF, 0xD8, 0xFF]), userNotes: nil)
        #expect(decomposition.mealDescription == "Chicken rice bowl")
        #expect(httpClient.recordedAttempts() == [
            GeminiModel.flashLite.rawValue,
            GeminiModel.flash.rawValue
        ])
    }

    @Test("router prefers gemini in auto when gemini key present")
    func routerPrefersGeminiInAuto() async throws {
        let store = APIKeyStore(service: "com.cameronro.helm.tests.\(UUID().uuidString)")
        try store.save("gemini-key", kind: .gemini)
        try store.save("openrouter-key", kind: .openRouter)

        let preferences = MealVisionPreferencesStore(
            defaults: UserDefaults(suiteName: "com.cameronro.helm.tests.\(UUID().uuidString)")!
        )
        preferences.backendPreference = .auto

        struct GeminiOnlyVision: MealMacroVisionProviding {
            func decompose(imageJPEGData: Data, userNotes: String?) async throws -> MealDecomposition {
                _ = imageJPEGData
                return MealDecomposition(
                    payload: MealDecompositionPayload(
                        schemaVersion: CoachOutputSchemaVersion.mealDecompositionV1.rawValue,
                        mealDescription: "Gemini routed meal",
                        items: [],
                        implicitFats: [],
                        portionNotes: nil
                    )
                )
            }

            func estimateMacrosDirect(imageJPEGData: Data, userNotes: String?) async throws -> MealEstimate {
                MealEstimate(
                    description: "Gemini routed meal",
                    caloriesKcal: 0,
                    proteinG: 0,
                    carbsG: 0,
                    fatG: 0,
                    confidence: .low
                )
            }
        }

        struct FailingOpenRouter: MealVisionProviding {
            func decompose(imageJPEGData: Data, userNotes: String?) async throws -> MealDecomposition {
                throw CoachProviderError.requestFailed("OpenRouter should not be called")
            }
        }

        let router = MealVisionRouter(
            apiKeyStore: store,
            preferences: preferences,
            geminiVision: GeminiOnlyVision(),
            openRouterVision: FailingOpenRouter()
        )

        let decomposition = try await router.decompose(imageJPEGData: Data([0xFF, 0xD8, 0xFF]), userNotes: nil)
        #expect(decomposition.mealDescription == "Gemini routed meal")
    }

    @Test("openrouter retries free slug when paid slug 404s")
    func openRouterRetriesFreeSlug() async throws {
        final class CountingOpenRouterHTTPClient: OpenRouterHTTPClient, @unchecked Sendable {
            private let lock = NSLock()
            private var attempts: [String] = []

            func chatCompletion(_ request: OpenRouterHTTPRequest) async throws -> Data {
                let model = (try? JSONDecoder().decode(ModelProbe.self, from: request.body))?.model ?? ""
                lock.withLock { attempts.append(model) }
                if !model.hasSuffix(":free") {
                    throw CoachProviderError.requestFailed(
                        "OpenRouter request failed with status 404: unavailable for free"
                    )
                }
                guard let url = Bundle.module.url(forResource: "openrouter_meal_decomposition", withExtension: "json") else {
                    throw CoachProviderError.requestFailed("Missing fixture")
                }
                return try Data(contentsOf: url)
            }

            func recordedAttempts() -> [String] {
                lock.withLock { attempts }
            }

            private struct ModelProbe: Decodable {
                let model: String
            }
        }

        let store = APIKeyStore(service: "com.cameronro.helm.tests.\(UUID().uuidString)")
        try store.save("fixture-key", kind: .openRouter)
        let httpClient = CountingOpenRouterHTTPClient()

        let vision = OpenRouterMealVisionProvider(
            apiKeyStore: store,
            httpClient: httpClient
        )

        let decomposition = try await vision.decompose(imageJPEGData: Data([0xFF, 0xD8, 0xFF]), userNotes: nil)
        #expect(decomposition.mealDescription == "Chicken rice bowl")
        #expect(httpClient.recordedAttempts() == [
            MealVisionModel.openRouterGemma.rawValue,
            MealVisionModel.openRouterGemmaFree.rawValue
        ])
    }

    @Test("router falls back to gemini when openrouter fails")
    func routerFallsBackToGemini() async throws {
        struct FailingOpenRouter: MealVisionProviding {
            func decompose(imageJPEGData: Data, userNotes: String?) async throws -> MealDecomposition {
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
            imageJPEGData: Data([0xFF, 0xD8, 0xFF]),
            userNotes: nil,
            progress: nil
        )
        #expect(estimate.lineItems.count == 3)
    }
}
