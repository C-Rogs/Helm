import Core
import Foundation
import OSLog

private let mealVisionLog = Logger(subsystem: "com.cameronro.helm", category: "NutritionKit")

public struct MealVisionRouter: Sendable {
    private let apiKeyStore: APIKeyStore
    private let preferences: MealVisionPreferencesStore
    private let geminiVision: any MealMacroVisionProviding
    private let openRouterVision: any MealMacroVisionProviding

    public init(
        apiKeyStore: APIKeyStore = APIKeyStore(),
        preferences: MealVisionPreferencesStore = MealVisionPreferencesStore(),
        geminiVision: (any MealMacroVisionProviding)? = nil,
        openRouterVision: (any MealMacroVisionProviding)? = nil
    ) {
        self.apiKeyStore = apiKeyStore
        self.preferences = preferences
        self.geminiVision = geminiVision ?? GeminiMealVisionProvider(apiKeyStore: apiKeyStore, preferences: preferences)
        self.openRouterVision = openRouterVision ?? OpenRouterMealVisionProvider(apiKeyStore: apiKeyStore)
    }

    public var isAvailable: Bool {
        hasOpenRouterKey || hasGeminiKey
    }

    public func decompose(imageJPEGData: Data, userNotes: String?) async throws -> MealDecomposition {
        let backend = resolvedBackend()
        mealVisionLog.debug(
            "Meal vision backend=\(backend.rawValue, privacy: .public) preference=\(preferences.backendPreference.rawValue, privacy: .public)"
        )

        switch backend {
        case .openRouter:
            do {
                return try await openRouterVision.decompose(imageJPEGData: imageJPEGData, userNotes: userNotes)
            } catch {
                guard hasGeminiKey else {
                    throw error
                }
                mealVisionLog.debug("Meal vision falling back to Gemini after OpenRouter failure")
                return try await geminiVision.decompose(imageJPEGData: imageJPEGData, userNotes: userNotes)
            }
        case .gemini:
            guard hasGeminiKey else {
                throw CoachProviderError.unavailable("Add your Gemini API key in Settings.")
            }
            return try await geminiVision.decompose(imageJPEGData: imageJPEGData, userNotes: userNotes)
        }
    }

    private enum ResolvedBackend: String {
        case openRouter
        case gemini
    }

    private func resolvedBackend() -> ResolvedBackend {
        switch preferences.backendPreference {
        case .openRouter:
            return hasOpenRouterKey ? .openRouter : (hasGeminiKey ? .gemini : .openRouter)
        case .gemini:
            return .gemini
        case .auto where hasGeminiKey:
            return .gemini
        case .auto where hasOpenRouterKey:
            return .openRouter
        case .auto:
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

extension MealVisionRouter: MealMacroVisionProviding {
    public func estimateMacrosDirect(imageJPEGData: Data, userNotes: String?) async throws -> MealEstimate {
        if hasGeminiKey {
            return try await geminiVision.estimateMacrosDirect(imageJPEGData: imageJPEGData, userNotes: userNotes)
        }
        throw CoachProviderError.unavailable("Direct macro vision needs a Gemini API key.")
    }

    public func draftMeal(imageJPEGData: Data, userNotes: String?) async throws -> MealVisionDraft {
        let backend = resolvedBackend()
        switch backend {
        case .openRouter:
            do {
                return try await openRouterVision.draftMeal(imageJPEGData: imageJPEGData, userNotes: userNotes)
            } catch {
                guard hasGeminiKey else { throw error }
                mealVisionLog.debug("Meal vision draft falling back to Gemini after OpenRouter failure")
                return try await geminiVision.draftMeal(imageJPEGData: imageJPEGData, userNotes: userNotes)
            }
        case .gemini:
            guard hasGeminiKey else {
                throw CoachProviderError.unavailable("Add your Gemini API key in Settings.")
            }
            return try await geminiVision.draftMeal(imageJPEGData: imageJPEGData, userNotes: userNotes)
        }
    }

    public func refineDraft(
        imageJPEGData: Data,
        priorDraft: MealVisionDraft,
        userCorrections: String,
        userNotes: String?
    ) async throws -> MealVisionDraft {
        let backend = resolvedBackend()
        switch backend {
        case .openRouter:
            do {
                return try await openRouterVision.refineDraft(
                    imageJPEGData: imageJPEGData,
                    priorDraft: priorDraft,
                    userCorrections: userCorrections,
                    userNotes: userNotes
                )
            } catch {
                guard hasGeminiKey else { throw error }
                mealVisionLog.debug("Meal vision refine falling back to Gemini after OpenRouter failure")
                return try await geminiVision.refineDraft(
                    imageJPEGData: imageJPEGData,
                    priorDraft: priorDraft,
                    userCorrections: userCorrections,
                    userNotes: userNotes
                )
            }
        case .gemini:
            guard hasGeminiKey else {
                throw CoachProviderError.unavailable("Add your Gemini API key in Settings.")
            }
            return try await geminiVision.refineDraft(
                imageJPEGData: imageJPEGData,
                priorDraft: priorDraft,
                userCorrections: userCorrections,
                userNotes: userNotes
            )
        }
    }
}

extension MealVisionRouter: MealVisionProviding {}
