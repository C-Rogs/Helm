import Core
import Foundation
import OSLog

private let mealVisionLog = Logger(subsystem: "com.cameronro.helm", category: "NutritionKit")

public struct GeminiMealVisionProvider: Sendable {
    private let apiKeyStore: APIKeyStore
    private let httpClient: any GeminiHTTPClient
    private let preferences: MealVisionPreferencesStore
    private let fixedModels: [GeminiModel]?

    public init(
        apiKeyStore: APIKeyStore = APIKeyStore(),
        httpClient: any GeminiHTTPClient = LiveGeminiHTTPClient(),
        preferences: MealVisionPreferencesStore = MealVisionPreferencesStore(),
        models: [GeminiModel]? = nil
    ) {
        self.apiKeyStore = apiKeyStore
        self.httpClient = httpClient
        self.preferences = preferences
        self.fixedModels = models
    }

    private var modelCandidates: [GeminiModel] {
        if let fixedModels, !fixedModels.isEmpty {
            return fixedModels
        }
        return preferences.geminiModelCandidates
    }

    public func decompose(imageJPEGData: Data, userNotes: String?) async throws -> MealDecomposition {
        let apiKey = try requireAPIKey()
        var lastError: Error?

        for model in modelCandidates {
            do {
                mealVisionLog.debug("Gemini meal vision begin model=\(model.rawValue, privacy: .public)")
                return try await decompose(
                    imageJPEGData: imageJPEGData,
                    apiKey: apiKey,
                    model: model,
                    userNotes: userNotes
                )
            } catch let error as CoachProviderError {
                guard Self.shouldRetryWithAlternateModel(error) else {
                    throw error
                }
                mealVisionLog.error(
                    "Gemini meal vision model failed model=\(model.rawValue, privacy: .public) error=\(CoachUserFacingError.message(for: error), privacy: .public)"
                )
                lastError = error
            }
        }

        throw lastError ?? CoachProviderError.unavailable("Gemini meal vision is unavailable.")
    }

    private func decompose(
        imageJPEGData: Data,
        apiKey: String,
        model: GeminiModel,
        userNotes: String?
    ) async throws -> MealDecomposition {
        let base64 = imageJPEGData.base64EncodedString()
        let requestID = UUID()

        let body = try GeminiRequestBuilder.mealDecompositionPhotoBody(
            systemInstructions: MealVisionPrompt.systemInstructions,
            imageJPEGBase64: base64,
            userMessage: MealVisionPrompt.userMessage(notes: userNotes)
        ).encoded()

        let request = GeminiGenerateHTTPRequest(
            requestID: requestID,
            model: model,
            apiKey: apiKey,
            body: body
        )

        let responseData = try await httpClient.generateContent(request)
        let jsonText = try GeminiSSEParser.responseText(from: responseData)
        let payload = try CoachStructuredOutputDecoder.decode(
            MealDecompositionPayload.self,
            from: jsonText,
            expectedSchema: .mealDecompositionV1
        )
        return MealDecomposition(payload: payload)
    }

    public func estimateMacrosDirect(imageJPEGData: Data, userNotes: String?) async throws -> MealEstimate {
        let apiKey = try requireAPIKey()
        var lastError: Error?

        for model in modelCandidates {
            do {
                return try await estimateMacrosDirect(
                    imageJPEGData: imageJPEGData,
                    apiKey: apiKey,
                    model: model,
                    userNotes: userNotes
                )
            } catch let error as CoachProviderError {
                guard Self.shouldRetryWithAlternateModel(error) else {
                    throw error
                }
                lastError = error
            }
        }

        throw lastError ?? CoachProviderError.unavailable("Gemini meal vision is unavailable.")
    }

    private func estimateMacrosDirect(
        imageJPEGData: Data,
        apiKey: String,
        model: GeminiModel,
        userNotes: String?
    ) async throws -> MealEstimate {
        let base64 = imageJPEGData.base64EncodedString()
        let requestID = UUID()

        let body = try GeminiRequestBuilder.mealEstimatePhotoBody(
            systemInstructions: MealVisionPrompt.directMacroSystemInstructions,
            imageJPEGBase64: base64,
            userMessage: MealVisionPrompt.directMacroUserMessage(notes: userNotes)
        ).encoded()

        let request = GeminiGenerateHTTPRequest(
            requestID: requestID,
            model: model,
            apiKey: apiKey,
            body: body
        )

        let responseData = try await httpClient.generateContent(request)
        let jsonText = try GeminiSSEParser.responseText(from: responseData)
        let payload = try CoachStructuredOutputDecoder.decode(
            MealEstimatePayload.self,
            from: jsonText,
            expectedSchema: .mealEstimateV1
        )
        return MealEstimate(payload: payload)
    }

    private static func shouldRetryWithAlternateModel(_ error: CoachProviderError) -> Bool {
        guard case .requestFailed(let detail) = error else { return false }
        let normalized = detail.lowercased()
        return normalized.contains("404")
            || normalized.contains("not found")
            || normalized.contains("no longer available")
    }

    private func requireAPIKey() throws -> String {
        guard let key = try apiKeyStore.load(kind: .gemini), !key.isEmpty else {
            throw CoachProviderError.unavailable("Add your Gemini API key in Settings.")
        }
        return key
    }
}

extension GeminiMealVisionProvider: MealMacroVisionProviding {}
