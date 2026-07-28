import Foundation

public struct OpenRouterMealVisionProvider: Sendable {
    private let apiKeyStore: APIKeyStore
    private let httpClient: any OpenRouterHTTPClient
    private let metadataStore: OpenRouterKeyMetadataStore

    public init(
        apiKeyStore: APIKeyStore = APIKeyStore(),
        httpClient: any OpenRouterHTTPClient = LiveOpenRouterHTTPClient(),
        metadataStore: OpenRouterKeyMetadataStore = OpenRouterKeyMetadataStore()
    ) {
        self.apiKeyStore = apiKeyStore
        self.httpClient = httpClient
        self.metadataStore = metadataStore
    }

    public func decompose(imageJPEGData: Data, userNotes: String?) async throws -> MealDecomposition {
        let apiKey = try requireAPIKey()
        let models = MealVisionModel.openRouterCandidates(freeModelsOnly: metadataStore.freeModelsOnly)
        var lastError: Error?

        for model in models {
            do {
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
                lastError = error
            }
        }

        throw lastError ?? CoachProviderError.unavailable("OpenRouter meal vision is unavailable.")
    }

    private func decompose(
        imageJPEGData: Data,
        apiKey: String,
        model: MealVisionModel,
        userNotes: String?
    ) async throws -> MealDecomposition {
        let base64 = imageJPEGData.base64EncodedString()
        let requestID = UUID()

        let body = try OpenRouterRequestBuilder.mealDecompositionPhotoBody(
            systemInstructions: MealVisionPrompt.systemInstructions,
            imageJPEGBase64: base64,
            model: model,
            userMessage: MealVisionPrompt.userMessage(notes: userNotes)
        )

        let request = OpenRouterHTTPRequest(requestID: requestID, apiKey: apiKey, body: body)
        let responseData = try await httpClient.chatCompletion(request)
        let jsonText = try OpenRouterResponseParser.messageText(from: responseData)
        let payload = try CoachStructuredOutputDecoder.decode(
            MealDecompositionPayload.self,
            from: jsonText,
            expectedSchema: .mealDecompositionV1
        )
        return MealDecomposition(payload: payload)
    }

    private static func shouldRetryWithAlternateModel(_ error: CoachProviderError) -> Bool {
        guard case .requestFailed(let detail) = error else { return false }
        let normalized = detail.lowercased()
        return normalized.contains("404")
            || normalized.contains("no endpoints found")
            || normalized.contains("no allowed providers")
            || normalized.contains("unavailable for free")
    }

    private func requireAPIKey() throws -> String {
        guard let key = try apiKeyStore.load(kind: .openRouter), !key.isEmpty else {
            throw CoachProviderError.unavailable("Add your OpenRouter API key in Settings.")
        }
        return key
    }
}

extension OpenRouterMealVisionProvider: MealVisionProviding {}
