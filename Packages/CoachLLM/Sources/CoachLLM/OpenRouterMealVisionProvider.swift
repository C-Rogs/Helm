import Foundation

public struct OpenRouterMealVisionProvider: Sendable {
    private let apiKeyStore: APIKeyStore
    private let httpClient: any OpenRouterHTTPClient
    private let model: MealVisionModel

    public init(
        apiKeyStore: APIKeyStore = APIKeyStore(),
        httpClient: any OpenRouterHTTPClient = LiveOpenRouterHTTPClient(),
        model: MealVisionModel = .openRouterGemma
    ) {
        self.apiKeyStore = apiKeyStore
        self.httpClient = httpClient
        self.model = model
    }

    public func decompose(imageJPEGData: Data) async throws -> MealDecomposition {
        let apiKey = try requireAPIKey()
        let base64 = imageJPEGData.base64EncodedString()
        let requestID = UUID()

        let body = try OpenRouterRequestBuilder.mealDecompositionPhotoBody(
            systemInstructions: MealVisionPrompt.systemInstructions,
            imageJPEGBase64: base64,
            model: model
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

    private func requireAPIKey() throws -> String {
        guard let key = try apiKeyStore.load(kind: .openRouter), !key.isEmpty else {
            throw CoachProviderError.unavailable("Add your OpenRouter API key in Settings.")
        }
        return key
    }
}

extension OpenRouterMealVisionProvider: MealVisionProviding {}
