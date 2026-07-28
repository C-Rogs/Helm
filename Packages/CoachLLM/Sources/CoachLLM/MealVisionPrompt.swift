import Foundation

public enum MealVisionBackendPreference: String, Sendable, CaseIterable, Codable {
    case auto
    case gemini
    case openRouter
}

public enum MealVisionModel: String, Sendable, Equatable {
    case geminiFlash = "gemini-2.5-flash"
    case openRouterGemmaFree = "google/gemma-3-27b-it:free"
    case openRouterGemma = "google/gemma-3-27b-it"

    /// OpenRouter model slugs to try for meal vision, ordered for the caller's key tier.
    public static func openRouterCandidates(freeModelsOnly: Bool) -> [MealVisionModel] {
        if freeModelsOnly {
            [.openRouterGemmaFree, .openRouterGemma]
        } else {
            [.openRouterGemma, .openRouterGemmaFree]
        }
    }
}

enum MealVisionPrompt {
    static let systemInstructions = """
    You decompose meal photos for a training athlete.
    List every visible and reasonably inferable edible component.
    Estimate grams per item; use plate, hand, or utensil scale when visible.
    Include likely hidden fats (oil, butter, dressing) in implicitFats.
    Do not output calories or macros.
    Round grams to whole numbers.
    Return only JSON matching the schema.
    When user context is provided, apply it to ingredient names and gram estimates.
    """

    static func userMessage(notes: String?) -> String {
        let base = "Decompose this meal photo into ingredients and estimated grams."
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return base }
        return "\(base) User context (must apply): \(trimmed)"
    }
}
