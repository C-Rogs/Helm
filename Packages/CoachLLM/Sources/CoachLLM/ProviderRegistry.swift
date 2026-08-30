/// One live provider instance per backend so `resetThread()` and prewarm state stay meaningful.
@MainActor
public final class ProviderRegistry {
    public static let shared = ProviderRegistry()

    private let foundationModelsProvider = ReservedFoundationModelsProvider()
    private let openRouterProvider = DisabledOpenRouterProvider()
    private var chatProvider: (any CoachLLMProvider)?

    public init() {}

    public func provider(for kind: ProviderKind) -> any CoachLLMProvider {
        switch kind {
        case .foundationModels:
            return foundationModelsProvider
        case .openRouter:
            return openRouterProvider
        case .gemini:
            if let chatProvider {
                return chatProvider
            }
            let placeholder = GeminiPlaceholderProvider()
            chatProvider = placeholder
            return placeholder
        }
    }

    public func installChatProvider(_ provider: any CoachLLMProvider) {
        chatProvider = provider
    }

    public func resetChatProvider() {
        chatProvider = nil
    }

    public func resetAllThreads() async {
        await foundationModelsProvider.resetThread()
        await openRouterProvider.resetThread()
        await chatProvider?.resetThread()
    }
}
