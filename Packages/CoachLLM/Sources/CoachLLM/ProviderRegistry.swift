/// One live provider instance per backend so `resetThread()` and prewarm state stay meaningful.
@MainActor
public final class ProviderRegistry {
    public static let shared = ProviderRegistry()

    private let foundationModelsProvider = ReservedFoundationModelsProvider()
    private let openRouterProvider = DisabledOpenRouterProvider()
    private var geminiProvider: (any CoachLLMProvider)?

    public init() {}

    public func provider(for kind: ProviderKind) -> any CoachLLMProvider {
        switch kind {
        case .foundationModels:
            return foundationModelsProvider
        case .openRouter:
            return openRouterProvider
        case .gemini:
            if let geminiProvider {
                return geminiProvider
            }
            let placeholder = GeminiPlaceholderProvider()
            geminiProvider = placeholder
            return placeholder
        }
    }

    /// M4.2 installs the live Gemini provider without changing the protocol surface.
    public func installGeminiProvider(_ provider: any CoachLLMProvider) {
        geminiProvider = provider
    }

    public func resetGeminiProvider() {
        geminiProvider = nil
    }

    public func resetAllThreads() async {
        await foundationModelsProvider.resetThread()
        await openRouterProvider.resetThread()
        await geminiProvider?.resetThread()
    }
}
