import Foundation

public enum MealVisionBackendPreference: String, Sendable, CaseIterable, Codable {
    case auto
    case gemini
    case openRouter
}

public enum MealVisionQualityPreference: String, Sendable, CaseIterable, Codable {
    case accurate
    case fast
}

public enum MealVisionModel: String, Sendable, Equatable {
    case geminiFlash = "gemini-3.5-flash"
    case openRouterGemmaFree = "google/gemma-3-27b-it:free"
    case openRouterGemma = "google/gemma-3-27b-it"

    /// OpenRouter model slugs to try for meal vision, ordered for the caller's key tier.
    /// Free slug often 404s now; always include paid slug as fallback.
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
    Name each item at UK CoFID specificity, including cooking method and fat medium when visible
    (e.g. "Potato chips, fried in commercial oil", not "potatoes").
    Put fats in implicitFats only when not already represented in item names:
    dressing on salad, oil on plainly cooked veg, butter on bread.
    Never add separate cooking oil when items are already fried, battered, coated, or named with a fat medium.
    Do not output calories or macros.
    Round grams to whole numbers.
    Return only JSON matching the schema.
    When user context is provided, apply it to ingredient names and gram estimates.
    Name ingredients in UK CoFID style when possible (e.g. "Cucumber, raw", "Cod, flesh only, grilled", "Cabbage, Chinese, raw", "Chicken, breast, grilled").
    Prefer a specific food species over generic words like "fish meat" or "white fish".
    """

    static func userMessage(notes: String?) -> String {
        let base = "Decompose this meal photo into ingredients and estimated grams."
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return base }
        return "\(base) User context (must apply): \(trimmed)"
    }

    static let directMacroSystemInstructions = """
    You estimate meal macros from photos for a training athlete.
    Return only JSON matching the schema. Round macros to whole grams and calories.
    When user context is provided, apply it to the estimate.
    """

    static func directMacroUserMessage(notes: String?) -> String {
        let base = "Estimate total meal macros from this photo."
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return base }
        return "\(base) User context (must apply): \(trimmed)"
    }

    static let draftSystemInstructions = """
    You draft meal components and macros from photos for a training athlete.
    List every visible and reasonably inferable edible component.
    For each item, run a portion meta check: assess visible thickness, slice count, surface area, stacking, and coverage relative to plate, hand, or utensil scale. Record this in portionMeta as a short factual sentence.
    Macros for each item must reflect that portion assessment (thick slices carry more grams and calories than thin slices; generous coverage is not a garnish).
    Do not assume default portion styles (e.g. sashimi-thin) unless the geometry supports it.
    Estimate grams and per-item calories, protein, carbs, and fat from the photo and portion meta.
    Round grams and macros to whole numbers.
    Return only JSON matching the schema.
    When user context is provided, apply it to names, grams, portionMeta, and macros.
    """

    static func draftUserMessage(notes: String?) -> String {
        let base = "Draft meal components, portion meta, and macros from this photo."
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return base }
        return "\(base) User context (must apply): \(trimmed)"
    }

    static let refineDraftSystemInstructions = """
    You refine a meal vision draft from a photo for a training athlete.
    You receive the prior draft JSON and user corrections. Apply corrections while re-checking the photo.
    Re-run the portion meta check for every item: thickness, slice count, surface area, stacking, and coverage vs plate/hand/utensil scale.
    Update portionMeta, grams, and per-item macros so they stay consistent with visible geometry and user corrections.
    Round grams and macros to whole numbers.
    Return only JSON matching the schema.
    """

    static func refineDraftUserMessage(
        priorDraftJSON: String,
        corrections: String,
        notes: String?
    ) -> String {
        var parts = [
            "Refine this meal draft using the photo.",
            "Prior draft JSON:\n\(priorDraftJSON)"
        ]
        let trimmedCorrections = corrections.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCorrections.isEmpty {
            parts.append("User corrections (must apply): \(trimmedCorrections)")
        }
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedNotes.isEmpty {
            parts.append("Original user context: \(trimmedNotes)")
        }
        return parts.joined(separator: "\n\n")
    }
}
