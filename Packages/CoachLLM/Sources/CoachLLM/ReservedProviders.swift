import Foundation

struct ReservedFoundationModelsProvider: CoachLLMProvider {
    nonisolated var id: String { "foundation-models" }
    nonisolated var displayName: String { "On-device" }
    nonisolated var kind: ProviderKind { .foundationModels }
    nonisolated let requiresNetwork = false

    nonisolated func availability() async -> ProviderAvailability {
        .unavailable(
            label: "Not available in v1",
            helpText: "On-device coaching is planned for a later release."
        )
    }

    nonisolated func prewarm() async {}

    func resetThread() async {}

    func respond(
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState
    ) async throws -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: CoachProviderError.unavailable("On-device coaching is not available yet."))
        }
    }
}

struct DisabledOpenRouterProvider: CoachLLMProvider {
    nonisolated var id: String { "openrouter-disabled" }
    nonisolated var displayName: String { "OpenRouter" }
    nonisolated var kind: ProviderKind { .openRouter }
    nonisolated let requiresNetwork = true

    nonisolated func availability() async -> ProviderAvailability {
        .unavailable(
            label: "Disabled",
            helpText: "OpenRouter support is reserved for a later release."
        )
    }

    nonisolated func prewarm() async {}

    func resetThread() async {}

    func respond(
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState
    ) async throws -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: CoachProviderError.unavailable("OpenRouter is not enabled yet."))
        }
    }
}

struct GeminiPlaceholderProvider: CoachLLMProvider {
    nonisolated var id: String { "gemini-placeholder" }
    nonisolated var displayName: String { "Gemini" }
    nonisolated var kind: ProviderKind { .gemini }
    nonisolated let requiresNetwork = true

    nonisolated func availability() async -> ProviderAvailability {
        .unavailable(
            label: "API key missing",
            helpText: "Add your Gemini API key in Settings."
        )
    }

    nonisolated func prewarm() async {}

    func resetThread() async {}

    func respond(
        systemInstructions: String,
        contextBlock: String,
        userMessage: String,
        thread: CoachThreadState
    ) async throws -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: CoachProviderError.unavailable("Add your Gemini API key in Settings."))
        }
    }
}
