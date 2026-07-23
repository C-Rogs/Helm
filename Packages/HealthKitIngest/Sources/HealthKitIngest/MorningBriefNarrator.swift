import CoachLLM
import Core
import Foundation

public struct MorningBriefNarrator: Sendable {
    public typealias NarrateHandler = @Sendable (CoachPrompt) async throws -> CoachStructuredArtefact<MorningBriefPayload>?

    private let narrateHandler: NarrateHandler

    public init(narrateHandler: @escaping NarrateHandler) {
        self.narrateHandler = narrateHandler
    }

    public static func live() -> MorningBriefNarrator {
        MorningBriefNarrator { prompt in
            try await liveNarrate(prompt: prompt)
        }
    }

    public func narrate(prompt: CoachPrompt) async throws -> CoachStructuredArtefact<MorningBriefPayload>? {
        try await narrateHandler(prompt)
    }

    private static func liveNarrate(prompt: CoachPrompt) async throws -> CoachStructuredArtefact<MorningBriefPayload>? {
        let preferences = ProviderPreferencesStore()
        let provider = await MainActor.run {
            ProviderRegistry.shared.provider(for: preferences.selectedProvider)
        }
        guard await provider.availability().isAvailable else { return nil }
        guard let gemini = provider as? GeminiProvider else { return nil }

        return try await gemini.generateMorningBrief(
            systemInstructions: prompt.systemInstructions,
            contextBlock: prompt.contextBlock,
            userMessage: "Write today's morning brief from the engine snapshot.",
            thread: .empty
        )
    }
}
