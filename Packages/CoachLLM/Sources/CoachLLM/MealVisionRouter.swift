import Foundation

public struct MealVisionRouter: Sendable {
    private let apiKeyStore: APIKeyStore
    private let preferences: MealVisionPreferencesStore
    private let geminiVision: GeminiMealVisionProvider
    private let openRouterVision: OpenRouterMealVisionProvider

    public init(
        apiKeyStore: APIKeyStore = APIKeyStore(),
        preferences: MealVisionPreferencesStore = MealVisionPreferencesStore(),
        geminiVision: GeminiMealVisionProvider? = nil,
        openRouterVision: OpenRouterMealVisionProvider? = nil
    ) {
        self.apiKeyStore = apiKeyStore
        self.preferences = preferences
        self.geminiVision = geminiVision ?? GeminiMealVisionProvider(apiKeyStore: apiKeyStore)
        self.openRouterVision = openRouterVision ?? OpenRouterMealVisionProvider(apiKeyStore: apiKeyStore)
    }

    public var isAvailable: Bool {
        hasOpenRouterKey || hasGeminiKey
    }

    public func decompose(imageJPEGData: Data) async throws -> MealDecomposition {
        switch resolvedBackend() {
        case .openRouter:
            return try await openRouterVision.decompose(imageJPEGData: imageJPEGData)
        case .gemini:
            return try await geminiVision.decompose(imageJPEGData: imageJPEGData)
        }
    }

    private enum ResolvedBackend {
        case openRouter
        case gemini
    }

    private func resolvedBackend() -> ResolvedBackend {
        switch preferences.backendPreference {
        case .openRouter where hasOpenRouterKey:
            return .openRouter
        case .gemini where hasGeminiKey:
            return .gemini
        case .auto where hasOpenRouterKey:
            return .openRouter
        case .auto where hasGeminiKey:
            return .gemini
        case .openRouter, .gemini, .auto:
            return hasGeminiKey ? .gemini : .openRouter
        }
    }

    private var hasOpenRouterKey: Bool {
        (try? apiKeyStore.load(kind: .openRouter)).map { !$0.isEmpty } ?? false
    }

    private var hasGeminiKey: Bool {
        (try? apiKeyStore.load(kind: .gemini)).map { !$0.isEmpty } ?? false
    }
}

extension MealVisionRouter: MealVisionProviding {}
