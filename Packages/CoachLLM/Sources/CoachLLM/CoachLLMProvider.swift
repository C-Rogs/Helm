/// LLM backend contract. Gemini, Foundation Models, and OpenRouter all conform.
public protocol CoachLLMProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var kind: ProviderKind { get }
    var requiresNetwork: Bool { get }

    func availability() async -> ProviderAvailability
    func prewarm() async
    func respond(
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState,
        freshnessSuffix: String?
    ) async throws -> AsyncThrowingStream<String, Error>
    /// Chat catalog turn. May emit function calls. `respond` stays tool-free (compaction, summaries).
    func respondTurn(
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState,
        freshnessSuffix: String?
    ) async throws -> AsyncThrowingStream<CoachLLMStreamEvent, Error>
    func resetThread() async

    func generateSessionAdjustment(
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState
    ) async throws -> CoachStructuredArtefact<SessionAdjustmentPayload>

    func generateWorkoutStart(
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState
    ) async throws -> CoachStructuredArtefact<WorkoutStartStructuredPayload>

    func generateMorningBrief(
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState
    ) async throws -> CoachStructuredArtefact<MorningBriefPayload>

    func generatePlanOptionCards(
        systemInstructions: String,
        userMessage: String
    ) async throws -> PlanOptionCardsPayload

    func classifyCalendarEvents(titles: [String]) async throws -> CalendarEventClassifyPayload
}

extension CoachLLMProvider {
    public func generateSessionAdjustment(
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState
    ) async throws -> CoachStructuredArtefact<SessionAdjustmentPayload> {
        throw CoachProviderError.unavailable(
            "Structured session adjustments are not available on this provider."
        )
    }

    public func generateWorkoutStart(
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState
    ) async throws -> CoachStructuredArtefact<WorkoutStartStructuredPayload> {
        throw CoachProviderError.unavailable(
            "Structured workout start is not available on this provider."
        )
    }

    public func generateMorningBrief(
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState
    ) async throws -> CoachStructuredArtefact<MorningBriefPayload> {
        throw CoachProviderError.unavailable(
            "Morning brief narration is not available on this provider."
        )
    }

    public func generatePlanOptionCards(
        systemInstructions: String,
        userMessage: String
    ) async throws -> PlanOptionCardsPayload {
        throw CoachProviderError.unavailable(
            "Plan option cards are not available on this provider."
        )
    }

    public func classifyCalendarEvents(titles: [String]) async throws -> CalendarEventClassifyPayload {
        throw CoachProviderError.unavailable(
            "Calendar classification is not available on this provider."
        )
    }
}
