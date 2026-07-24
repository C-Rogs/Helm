import Foundation

public struct GeminiMealVisionProvider: Sendable {
    private let apiKeyStore: APIKeyStore
    private let httpClient: any GeminiHTTPClient
    private let model: GeminiModel

    public init(
        apiKeyStore: APIKeyStore = APIKeyStore(),
        httpClient: any GeminiHTTPClient = LiveGeminiHTTPClient(),
        model: GeminiModel = .mealVision
    ) {
        self.apiKeyStore = apiKeyStore
        self.httpClient = httpClient
        self.model = model
    }

    public func decompose(imageJPEGData: Data) async throws -> MealDecomposition {
        let apiKey = try requireAPIKey()
        let base64 = imageJPEGData.base64EncodedString()
        let requestID = UUID()

        let body = try GeminiRequestBuilder.mealDecompositionPhotoBody(
            systemInstructions: MealVisionPrompt.systemInstructions,
            imageJPEGBase64: base64
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

    private func requireAPIKey() throws -> String {
        guard let key = try apiKeyStore.load(kind: .gemini), !key.isEmpty else {
            throw CoachProviderError.unavailable("Add your Gemini API key in Settings.")
        }
        return key
    }
}

extension GeminiMealVisionProvider: MealVisionProviding {}
