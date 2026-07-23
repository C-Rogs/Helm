import CoachLLM
import Foundation

enum CoachBootstrap {
    static func start() {
        Task { @MainActor in
            installGeminiIfPossible()
        }
    }

    @MainActor
    private static func installGeminiIfPossible() {
        let keyStore = APIKeyStore()
        guard keyStore.hasKey(kind: .gemini) else { return }
        let provider = GeminiProvider(apiKeyStore: keyStore)
        ProviderRegistry.shared.installGeminiProvider(provider)
    }
}
