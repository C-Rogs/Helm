import CoachLLM
import Foundation

enum CoachBootstrap {
    static func start() {
        Task { @MainActor in
            installProvider()
            #if !DEBUG
            _ = await OpenRouterKeyProvisioner.provisionIfNeeded()
            #endif
        }
    }

    @MainActor
    static var calendarClassifierProvider: (any CoachLLMProvider)? {
        let keyStore = APIKeyStore()
        guard keyStore.hasKey(kind: .gemini) else { return nil }
        return GeminiProvider(apiKeyStore: keyStore, model: .calendar)
    }

    @MainActor
    private static func installProvider() {
        let keyStore = APIKeyStore()
        if keyStore.hasKey(kind: .gemini) {
            let provider = GeminiProvider(apiKeyStore: keyStore)
            ProviderRegistry.shared.installGeminiProvider(provider)
            return
        }

        #if DEBUG
        let mock = MockProvider(
            id: "mock-coach",
            displayName: "Mock Coach",
            configuration: MockProvider.Configuration(
                responseChunks: [
                    "Based on your stored readiness and training context, ",
                    "recovery looks moderate today. ",
                    "Keep volume steady and aim for RIR 2 on compounds."
                ]
            )
        )
        ProviderRegistry.shared.installGeminiProvider(mock)
        #endif
    }
}
