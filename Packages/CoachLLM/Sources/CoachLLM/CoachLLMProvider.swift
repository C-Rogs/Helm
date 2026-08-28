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
}
