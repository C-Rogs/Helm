import Foundation
#if canImport(Diagnostics)
import Diagnostics
#endif
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
        model: GeminiModel = .default,
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
        let payload: Payload
        do {
            payload = try decodeStructuredPayload(
                type,
                responseData: responseData,
                expectedSchema: expectedSchema
            )
        } catch let error as CoachStructuredOutputError {
            guard case .schemaVersionMismatch = error else {
                await logStructuredDecodeFailure(
                    requestID: requestID,
                    promptVersion: promptVersion,
                    error: error,
                    jsonSnippet: responseSnippet(from: responseData)
                )
                throw error
            }

            coachLLMLog.debug(
                "Gemini structured decode retry requestID=\(requestID.uuidString, privacy: .public) prompt=\(promptVersion.rawValue, privacy: .public)"
            )
            let retryData = try await httpClient.generateContent(request)
            do {
                payload = try decodeStructuredPayload(
                    type,
                    responseData: retryData,
                    expectedSchema: expectedSchema
                )
            } catch {
                await logStructuredDecodeFailure(
                    requestID: requestID,
                    promptVersion: promptVersion,
                    error: error,
                    jsonSnippet: responseSnippet(from: retryData)
                )
                throw error
            }
        } catch {
            await logStructuredDecodeFailure(
                requestID: requestID,
                promptVersion: promptVersion,
                error: error,
                jsonSnippet: responseSnippet(from: responseData)
            )
            throw error
        }

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

    public func estimateMacros(
        imageJPEGData: Data
    ) async throws -> CoachStructuredArtefact<MealEstimatePayload> {
        let base64 = imageJPEGData.base64EncodedString()
        let systemInstructions = """
        You estimate meal macros from photos for a training athlete.
        Return only JSON matching the schema. Round macros to whole grams and calories.
        """
        return try await generateStructured(
            MealEstimatePayload.self,
            systemInstructions: systemInstructions,
            contextBlock: "",
            userMessage: "Estimate the meal macros from this photo.",
            thread: .empty,
            expectedSchema: .mealEstimateV1,
            promptVersion: .mealEstimateV1
        ) {
            try GeminiRequestBuilder.mealEstimatePhotoBody(
                systemInstructions: systemInstructions,
                imageJPEGBase64: base64
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

    private func decodeStructuredPayload<Payload: Decodable>(
        _ type: Payload.Type,
        responseData: Data,
        expectedSchema: CoachOutputSchemaVersion
    ) throws -> Payload {
        let jsonText = try GeminiSSEParser.responseText(from: responseData)
        return try CoachStructuredOutputDecoder.decode(
            type,
            from: jsonText,
            expectedSchema: expectedSchema
        )
    }

    private func responseSnippet(from responseData: Data) -> String {
        let jsonText = (try? GeminiSSEParser.responseText(from: responseData)) ?? ""
        return String(jsonText.prefix(240))
    }

    private func logStructuredDecodeFailure(
        requestID: UUID,
        promptVersion: CoachPromptVersion,
        error: Error,
        jsonSnippet: String
    ) async {
        let snippet = String(jsonSnippet.prefix(240))
        coachLLMLog.error(
            "Gemini structured decode failed requestID=\(requestID.uuidString, privacy: .public) prompt=\(promptVersion.rawValue, privacy: .public)"
        )
        #if canImport(Diagnostics)
        await DiagnosticsLog.shared.record(
            category: .coachLLM,
            level: .error,
            message: "Structured output decode failed",
            context: [
                "requestID": requestID.uuidString,
                "promptVersion": promptVersion.rawValue,
                "error": String(describing: type(of: error)),
                "jsonSnippet": snippet
            ]
        )
        #endif
    }
}
