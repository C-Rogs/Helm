import CoachLLM
import Foundation

enum CoachBootstrap {
    @MainActor
    static func start() {
        refreshProvider()
        #if !DEBUG
        if CloudFeatureConsentPreferences.shared.isConsented {
            Task { @MainActor in
                _ = await OpenRouterKeyProvisioner.provisionIfNeeded()
            }
        }
        #endif
    }

    @MainActor
    static func refreshProvider() {
        ProviderRegistry.shared.resetChatProvider()
        guard CloudFeatureConsentPreferences.shared.isConsented else { return }
        installProvider()
    }

    @MainActor
    static var calendarClassifierProvider: (any CoachLLMProvider)? {
        guard CloudFeatureConsentPreferences.shared.isConsented else { return nil }
        let keyStore = APIKeyStore()
        guard keyStore.hasKey(kind: .gemini) else { return nil }
        return GeminiProvider(apiKeyStore: keyStore, model: .calendar)
    }

    @MainActor
    private static func installProvider() {
        guard CloudFeatureConsentPreferences.shared.isConsented else { return }
        let keyStore = APIKeyStore()
        if keyStore.hasKey(kind: .gemini) {
            let provider = GeminiProvider(apiKeyStore: keyStore)
            ProviderRegistry.shared.installChatProvider(provider)
            Task { await provider.prewarm() }
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
            ProviderRegistry.shared.installChatProvider(mock)
        #endif
    }
}
