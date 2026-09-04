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

    public func prewarm() async {
        guard let key = try? apiKeyStore.load(kind: .gemini), !key.isEmpty else { return }
        await httpClient.prewarm()
    }

    public func resetThread() async {}

    public func respond(
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState,
        freshnessSuffix: String? = nil
    ) async throws -> AsyncThrowingStream<String, Error> {
        let textStream = GeminiStreamAssembler.textChunks(
            from: try await streamByteStream(
                systemInstructions: systemInstructions,
                contextBlock: contextBlock,
                userMessage: userMessage,
                thread: thread,
                freshnessSuffix: freshnessSuffix,
                includeCatalogTools: false
            )
        )
        return textStream
    }

    /// Chat catalog turn. Compaction and other non-chat streams stay on `respond`.
    public func respondTurn(
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState,
        freshnessSuffix: String? = nil
    ) async throws -> AsyncThrowingStream<CoachLLMStreamEvent, Error> {
        GeminiStreamAssembler.events(
            from: try await streamByteStream(
                systemInstructions: systemInstructions,
                contextBlock: contextBlock,
                userMessage: userMessage,
                thread: thread,
                freshnessSuffix: freshnessSuffix,
                includeCatalogTools: true
            )
        )
    }

    private func streamByteStream(
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState,
        freshnessSuffix: String?,
        includeCatalogTools: Bool
    ) async throws -> AsyncThrowingStream<Data, Error> {
        let apiKey = try requireAPIKey()
        let requestID = UUID()
        let signpostID = CoachLLMInstrumentation.beginGeminiStream(requestID: requestID)
        coachLLMLog.debug("Gemini stream begin requestID=\(requestID.uuidString, privacy: .public)")

        let body = try GeminiRequestBuilder.streamChatBody(
            systemInstructions: systemInstructions,
            contextBlock: contextBlock,
            userMessage: userMessage,
            thread: thread,
            freshnessSuffix: freshnessSuffix,
            includeCatalogTools: includeCatalogTools
        ).encoded()

        let request = GeminiStreamHTTPRequest(
            requestID: requestID,
            model: model,
            apiKey: apiKey,
            body: body
        )

        let byteStream = try await httpClient.streamGenerate(request)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in byteStream {
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
        if let usage = GeminiSSEParser.usageMetadata(fromResponseData: responseData) {
            coachLLMLog.debug(
                "Gemini generate usage requestID=\(requestID.uuidString, privacy: .public) \(usage.summary, privacy: .public)"
            )
        }
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
            if let usage = GeminiSSEParser.usageMetadata(fromResponseData: retryData) {
                coachLLMLog.debug(
                    "Gemini generate retry usage requestID=\(requestID.uuidString, privacy: .public) \(usage.summary, privacy: .public)"
                )
            }
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
            promptVersion: promptVersion,
            requestID: requestID
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
            expectedSchema: .sessionAdjustmentV2,
            promptVersion: .sessionAdjustmentV2
        ) {
            try GeminiRequestBuilder.sessionAdjustmentBody(
                systemInstructions: systemInstructions,
                contextBlock: contextBlock,
                userMessage: userMessage,
                thread: thread
            )
        }
    }

    public func generateWorkoutStart(
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState
    ) async throws -> CoachStructuredArtefact<WorkoutStartStructuredPayload> {
        try await generateStructured(
            WorkoutStartStructuredPayload.self,
            systemInstructions: systemInstructions,
            contextBlock: contextBlock,
            userMessage: userMessage,
            thread: thread,
            expectedSchema: .workoutStartV2,
            promptVersion: .chatV1
        ) {
            try GeminiRequestBuilder.workoutStartBody(
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

    public func classifyCalendarEvents(
        titles: [String]
    ) async throws -> CalendarEventClassifyPayload {
        let systemInstructions = """
        You classify calendar event titles for a training app.
        Rules:
        - fullyBlocking: the event consumes the entire day (all-day conference, wedding, travel, full-day hike, moving day, festival).
        - partiallyBlocking: the event is social, an appointment, or time-limited (drinks, dinner, dentist, see a friend, haircut, coffee, meeting, deadline day, evening plans).
        - If a title is ambiguous (e.g. "Deadline"), default to fullyBlocking.
        - Return every title exactly as given, with its classification.
        """
        return try await generateStructured(
            CalendarEventClassifyPayload.self,
            systemInstructions: systemInstructions,
            contextBlock: "",
            userMessage: "",
            thread: .empty,
            expectedSchema: .calendarEventClassifyV1,
            promptVersion: .calendarEventClassifyV1
        ) {
            try GeminiRequestBuilder.calendarEventClassifyBody(
                systemInstructions: systemInstructions,
                titles: titles
            )
        }.payload
    }

    public func generatePatternDiscovery(
        schemaLines: String
    ) async throws -> PatternDiscoveryPayload {
        let systemInstructions = """
        You propose at most 5 on-device N-of-1 hypotheses as JSON. The app computes numbers later.
        Propose AST only. Never invent correlations or dump day logs.
        Legal exposure ops: present or absent for binary fields; tertile_low or tertile_high for continuous; \
        residual_positive or residual_non_positive for residual; band_equals for categorical (set exposureBand).
        Outcomes must be continuous or residual fields, never binary or categorical.
        Lag 0 to 3. Alcohol to next-morning sleep, RHR, or HRV uses lag 1.
        Do not propose HRV or ARC as exposure against raw workout minutes or session volume.
        Only use fields present in the coverage list. Prefer high n. Return fewer than 5 if coverage is thin.
        """
        return try await generateStructured(
            PatternDiscoveryPayload.self,
            systemInstructions: systemInstructions,
            contextBlock: "",
            userMessage: "",
            thread: .empty,
            expectedSchema: .patternDiscoveryV1,
            promptVersion: .patternDiscoveryV1
        ) {
            try GeminiRequestBuilder.patternDiscoveryBody(
                systemInstructions: systemInstructions,
                schemaLines: schemaLines
            )
        }.payload
    }

    public func generatePlanOptionCards(
        systemInstructions: String,
        userMessage: String
    ) async throws -> PlanOptionCardsPayload {
        try await generateStructured(
            PlanOptionCardsPayload.self,
            systemInstructions: systemInstructions,
            contextBlock: "",
            userMessage: "",
            thread: .empty,
            expectedSchema: .planOptionCardsV1,
            promptVersion: .planOptionCardsV1
        ) {
            try GeminiRequestBuilder.planOptionCardsBody(
                systemInstructions: systemInstructions,
                userMessage: userMessage
            )
        }.payload
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
