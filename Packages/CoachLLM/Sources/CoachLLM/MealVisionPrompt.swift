import Foundation

public enum MealVisionBackendPreference: String, Sendable, CaseIterable, Codable {
    case auto
    case gemini
    case openRouter
}

public enum MealVisionModel: String, Sendable, Equatable {
    case geminiFlash = "gemini-2.5-flash"
    case openRouterGemma = "google/gemma-3-27b-it:free"
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
    """
}
