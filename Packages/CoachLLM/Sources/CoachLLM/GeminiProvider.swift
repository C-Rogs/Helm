import Foundation
import OSLog

private let coachLLMLog = Logger(subsystem: "com.cameronro.helm", category: "CoachLLM")

public final class GeminiProvider: CoachLLMProvider, @unchecked Sendable {
    public let id = "gemini"
    public let displayName = "Gemini"
    public let kind: ProviderKind = .gemini
    public let requiresNetwork = true

    private let apiKeyStore: APIKeyStore
    private let httpClient: any GeminiHTTPClient
    private let model: GeminiModel
    private let preferences: ProviderPreferencesStore

    public init(
        apiKeyStore: APIKeyStore = APIKeyStore(),
        httpClient: any GeminiHTTPClient = LiveGeminiHTTPClient(),
        model: GeminiModel = .flash,
        preferences: ProviderPreferencesStore = ProviderPreferencesStore()
    ) {
        self.apiKeyStore = apiKeyStore
        self.httpClient = httpClient
        self.model = model
        self.preferences = preferences
    }

    public func availability() async -> ProviderAvailability {
        guard let key = try? apiKeyStore.load(kind: .gemini), !key.isEmpty else {
            return .unavailable(
                label: "API key missing",
                helpText: "Add your Gemini API key in Settings."
            )
        }
        _ = preferences
        return .available
    }

    public func prewarm() async {}

    public func resetThread() async {}

    public func respond(
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState
    ) async throws -> AsyncThrowingStream<String, Error> {
        let apiKey = try requireAPIKey()
        let requestID = UUID()
        let signpostID = CoachLLMInstrumentation.beginGeminiStream(requestID: requestID)
        coachLLMLog.debug("Gemini stream begin requestID=\(requestID.uuidString, privacy: .public)")

        let body = try GeminiRequestBuilder.streamChatBody(
            systemInstructions: systemInstructions,
            contextBlock: contextBlock,
            userMessage: userMessage,
            thread: thread
        ).encoded()

        let request = GeminiStreamHTTPRequest(
            requestID: requestID,
            model: model,
            apiKey: apiKey,
            body: body
        )

        let byteStream = try await httpClient.streamGenerate(request)
        let textStream = GeminiStreamAssembler.textChunks(from: byteStream)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in textStream {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                    CoachLLMInstrumentation.endGeminiStream(requestID: requestID, signpostID: signpostID)
                    coachLLMLog.debug("Gemini stream end requestID=\(requestID.uuidString, privacy: .public)")
                } catch {
                    CoachLLMInstrumentation.endGeminiStream(requestID: requestID, signpostID: signpostID)
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func generateStructured<Payload: Decodable & Equatable & Sendable>(
        _ type: Payload.Type,
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState,
        expectedSchema: CoachOutputSchemaVersion,
        promptVersion: CoachPromptVersion,
        bodyBuilder: () throws -> GeminiGenerateRequestBody
    ) async throws -> CoachStructuredArtefact<Payload> {
        let apiKey = try requireAPIKey()
        let requestID = UUID()
        coachLLMLog.debug("Gemini generate begin requestID=\(requestID.uuidString, privacy: .public)")

        let body = try bodyBuilder().encoded()
        let request = GeminiGenerateHTTPRequest(
            requestID: requestID,
            model: model,
            apiKey: apiKey,
            body: body
        )

        let responseData = try await httpClient.generateContent(request)
        let jsonText = try GeminiSSEParser.responseText(from: responseData)
        let payload = try CoachStructuredOutputDecoder.decode(
            type,
            from: jsonText,
            expectedSchema: expectedSchema
        )

        coachLLMLog.debug("Gemini generate end requestID=\(requestID.uuidString, privacy: .public)")
        return CoachStructuredArtefact(
            payload: payload,
            schemaVersion: expectedSchema,
            promptVersion: promptVersion
        )
    }

    public func generateSessionAdjustment(
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState
    ) async throws -> CoachStructuredArtefact<SessionAdjustmentPayload> {
        try await generateStructured(
            SessionAdjustmentPayload.self,
            systemInstructions: systemInstructions,
            contextBlock: contextBlock,
            userMessage: userMessage,
            thread: thread,
            expectedSchema: .sessionAdjustmentV1,
            promptVersion: .sessionAdjustmentV1
        ) {
            try GeminiRequestBuilder.sessionAdjustmentBody(
                systemInstructions: systemInstructions,
                contextBlock: contextBlock,
                userMessage: userMessage,
                thread: thread
            )
        }
    }

    public func generateMealEstimate(
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState
    ) async throws -> CoachStructuredArtefact<MealEstimatePayload> {
        try await generateStructured(
            MealEstimatePayload.self,
            systemInstructions: systemInstructions,
            contextBlock: contextBlock,
            userMessage: userMessage,
            thread: thread,
            expectedSchema: .mealEstimateV1,
            promptVersion: .mealEstimateV1
        ) {
            try GeminiRequestBuilder.mealEstimateBody(
                systemInstructions: systemInstructions,
                contextBlock: contextBlock,
                userMessage: userMessage,
                thread: thread
            )
        }
    }

    public func generateMorningBrief(
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState
    ) async throws -> CoachStructuredArtefact<MorningBriefPayload> {
        try await generateStructured(
            MorningBriefPayload.self,
            systemInstructions: systemInstructions,
            contextBlock: contextBlock,
            userMessage: userMessage,
            thread: thread,
            expectedSchema: .briefV1,
            promptVersion: .briefV1
        ) {
            try GeminiRequestBuilder.morningBriefBody(
                systemInstructions: systemInstructions,
                contextBlock: contextBlock,
                userMessage: userMessage,
                thread: thread
            )
        }
    }

    private func requireAPIKey() throws -> String {
        guard let key = try apiKeyStore.load(kind: .gemini), !key.isEmpty else {
            throw CoachProviderError.unavailable("Add your Gemini API key in Settings.")
        }
        return key
    }
}
