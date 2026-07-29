import Foundation

/// How cooking fat is accounted for on a CoFID-resolved line item.
public enum CookingFatAttribution: Sendable, Equatable {
    /// Matched CoFID row already includes cooking fat (fried, battered, in-oil prep, etc.).
    case includedInRow
    /// Naturally fatty food; no separate cooking-fat line expected.
    case intrinsic
    /// Lean base where dressing/oil may be added on top.
    case additiveCandidate
}

public enum CookingFatAttributionClassifier: Sendable {
    public static func classify(
        itemName: String,
        cofidDescription: String,
        fatGPer100g: Double
    ) -> CookingFatAttribution {
        let name = NutritionLookup.normalize(itemName)
        let description = NutritionLookup.normalize(cofidDescription)

        if descriptionIncludesCookingFat(description) || descriptionIncludesCookingFat(name) {
            return .includedInRow
        }

        if isIntrinsicallyFatty(name: name, description: description, fatGPer100g: fatGPer100g) {
            return .intrinsic
        }

        if fatGPer100g >= 8, !isLeanPreparation(description) {
            return .includedInRow
        }

        return .additiveCandidate
    }

    public static func descriptionIncludesCookingFat(_ normalizedText: String) -> Bool {
        guard !normalizedText.isEmpty else { return false }

        for pattern in cookingFatPatterns where normalizedText.contains(pattern) {
            return true
        }
        return false
    }

    private static func isIntrinsicallyFatty(
        name: String,
        description: String,
        fatGPer100g: Double
    ) -> Bool {
        let combined = "\(name) \(description)"
        for token in intrinsicFatTokens where combined.contains(token) {
            return true
        }
        return fatGPer100g >= 12 && !isLeanProtein(description)
    }

    private static func isLeanPreparation(_ normalizedDescription: String) -> Bool {
        leanPreparationTokens.contains { normalizedDescription.contains($0) }
    }

    private static func isLeanProtein(_ normalizedDescription: String) -> Bool {
        leanProteinTokens.contains { normalizedDescription.contains($0) }
    }

    private static let cookingFatPatterns: [String] = [
        "fried",
        "batter",
        "battered",
        "coated",
        "crispy",
        "crumbed",
        "breaded",
        "stir fried",
        "stir-fried",
        "deep fried",
        "deep-fried",
        "tempura",
        "fritter",
        "croquette",
        "pastry",
        "in corn oil",
        "in vegetable oil",
        "in rapeseed oil",
        "in olive oil",
        "in sunflower oil",
        "in blended vegetable oil",
        "in commercial oil",
        "in dripping",
        "in beef dripping",
        "with butter",
        "butter and",
        "butter ghee",
        "in milk butter",
        "roasted in",
        "sauteed",
        "sautéed",
        "dressing",
        "mayonnaise",
        "mayo",
        "aioli",
        "hollandaise",
        "pesto",
        "takeaway",
        "fast food",
        "fish and chip",
        "potato chips",
    ]

    private static let leanPreparationTokens: [String] = [
        "grilled",
        "steamed",
        "boiled",
        "microwaved",
        "poached",
        "raw",
        "baked",
    ]

    private static let leanProteinTokens: [String] = [
        "chicken breast",
        "turkey breast",
        "cod",
        "haddock",
        "sole",
        "prawn",
        "shrimp",
        "white fish",
    ]

    private static let intrinsicFatTokens: [String] = [
        "cheese",
        "almond",
        "walnut",
        "peanut",
        "cashew",
        "pecan",
        "hazelnut",
        "pistachio",
        "macadamia",
        "avocado",
        "salmon",
        "mackerel",
        "sardine",
        "herring",
        "trout",
        "coconut milk",
        "cream",
        "bacon",
        "sausage",
        "nut butter",
    ]
}
