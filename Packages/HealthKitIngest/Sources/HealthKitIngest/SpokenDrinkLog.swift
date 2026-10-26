import CoachLLM
import Foundation

/// Corrects a dictated drink when the model picks an alcohol-free row or the wrong count.
public enum SpokenDrinkLog {
    public static func corrected(_ payload: FoodLogPayload, spoken: String) -> FoodLogPayload {
        guard payload.action == .log, let match = match(in: spoken) else { return payload }
        let macros = match.preset.macros(quantity: match.quantity)
        let drinkName = displayName(quantity: match.quantity, preset: match.preset)
        let items = payload.items ?? []
        let otherItems = items.filter { !isDrinkItem($0.name) }

        if otherItems.isEmpty {
            if hasOtherFood(in: payload.description) {
                return drinkBesideUnsplitMeal(payload, macros: macros, drinkName: drinkName)
            }
            return drinkOnly(payload, macros: macros, drinkName: drinkName)
        }

        return replacingDrinkItems(
            payload,
            macros: macros,
            drinkName: drinkName,
            quantity: match.quantity
        )
    }

    static func match(in spoken: String) -> (preset: AlcoholDrinkPreset, quantity: Int)? {
        let lower = spoken.lowercased()
        if isAlcoholFreeClaim(lower) { return nil }
        guard mentionsCorrectableBeer(lower) else { return nil }
        return (.beerPint, quantity(in: lower))
    }

    /// Line items carry grams, not macros. A drink line means the recorded total already
    /// includes a drink estimate, so the pint is renamed and not added again.
    /// A meal with no drink line gains the pint on top.
    private static func replacingDrinkItems(
        _ payload: FoodLogPayload,
        macros: FoodPortionMacros,
        drinkName: String,
        quantity: Int
    ) -> FoodLogPayload {
        var drinkInserted = false
        var hadDrinkLine = false
        var lines: [MealDecompositionPayload.Item] = []
        for item in payload.items ?? [] {
            if isDrinkItem(item.name) {
                hadDrinkLine = true
                if !drinkInserted {
                    lines.append(beerItem(name: drinkName, quantity: quantity))
                    drinkInserted = true
                }
            } else {
                lines.append(item)
            }
        }
        if !drinkInserted {
            lines.append(beerItem(name: drinkName, quantity: quantity))
        }
        let calories = hadDrinkLine ? payload.caloriesKcal : (payload.caloriesKcal ?? 0) + macros.energyKcal
        let protein = hadDrinkLine ? payload.proteinG : (payload.proteinG ?? 0) + macros.proteinG
        let carbs = hadDrinkLine ? payload.carbsG : (payload.carbsG ?? 0) + macros.carbsG
        let fat = hadDrinkLine ? payload.fatG : (payload.fatG ?? 0) + macros.fatG
        return copy(
            payload,
            description: payload.description,
            caloriesKcal: calories,
            proteinG: protein,
            carbsG: carbs,
            fatG: fat,
            items: lines,
            implicitFats: payload.implicitFats,
            portionNotes: payload.portionNotes
        )
    }

    /// No separable food lines. Keep the other words. Add a pint only when the text does not
    /// already name a drink, so a burger-and-lager total is not charged twice.
    private static func drinkBesideUnsplitMeal(
        _ payload: FoodLogPayload,
        macros: FoodPortionMacros,
        drinkName: String
    ) -> FoodLogPayload {
        let description = descriptionKeepingOtherFood(payload.description, drinkName: drinkName)
        if mentionsDrink(payload.description) {
            return copy(
                payload,
                description: description,
                caloriesKcal: payload.caloriesKcal,
                proteinG: payload.proteinG,
                carbsG: payload.carbsG,
                fatG: payload.fatG,
                items: nil,
                implicitFats: payload.implicitFats,
                portionNotes: payload.portionNotes
            )
        }
        return copy(
            payload,
            description: description,
            caloriesKcal: (payload.caloriesKcal ?? 0) + macros.energyKcal,
            proteinG: (payload.proteinG ?? 0) + macros.proteinG,
            carbsG: (payload.carbsG ?? 0) + macros.carbsG,
            fatG: (payload.fatG ?? 0) + macros.fatG,
            items: nil,
            implicitFats: payload.implicitFats,
            portionNotes: payload.portionNotes
        )
    }

    private static func drinkOnly(
        _ payload: FoodLogPayload,
        macros: FoodPortionMacros,
        drinkName: String
    ) -> FoodLogPayload {
        FoodLogPayload(
            schemaVersion: payload.schemaVersion,
            reply: payload.reply,
            action: .log,
            mealID: payload.mealID,
            description: drinkName,
            bucket: payload.bucket,
            caloriesKcal: macros.energyKcal,
            proteinG: macros.proteinG,
            carbsG: macros.carbsG,
            fatG: macros.fatG,
            helmDay: payload.helmDay,
            items: nil,
            implicitFats: nil,
            portionNotes: nil
        )
    }

    private static func copy(
        _ payload: FoodLogPayload,
        description: String?,
        caloriesKcal: Double?,
        proteinG: Double?,
        carbsG: Double?,
        fatG: Double?,
        items: [MealDecompositionPayload.Item]?,
        implicitFats: [MealDecompositionPayload.Item]?,
        portionNotes: String?
    ) -> FoodLogPayload {
        FoodLogPayload(
            schemaVersion: payload.schemaVersion,
            reply: payload.reply,
            action: .log,
            mealID: payload.mealID,
            description: description,
            bucket: payload.bucket,
            caloriesKcal: caloriesKcal,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            helmDay: payload.helmDay,
            items: items,
            implicitFats: implicitFats,
            portionNotes: portionNotes
        )
    }

    private static func displayName(quantity: Int, preset: AlcoholDrinkPreset) -> String {
        quantity == 1 ? preset.displayName : "\(quantity) × \(preset.displayName)"
    }

    private static func beerItem(name: String, quantity: Int) -> MealDecompositionPayload.Item {
        MealDecompositionPayload.Item(
            name: name,
            estimatedGrams: gramsPerPint * Double(max(quantity, 1)),
            confidence: .high
        )
    }

    private static func mentionsCorrectableBeer(_ lower: String) -> Bool {
        if lower.contains("pint"), containsBeerWord(lower) { return true }
        return lower.range(
            of: #"\b(a|an)\s+(lager|beer|ale|stout)s?\b|\bhad\s+(a\s+|an\s+)?(lager|beer|ale|stout)s?\b"#,
            options: .regularExpression
        ) != nil
    }

    private static func isAlcoholFreeClaim(_ lower: String) -> Bool {
        lower.contains("alcohol-free")
            || lower.contains("alcohol free")
            || lower.contains("non-alcoholic")
            || lower.contains("non alcoholic")
            || lower.contains("0.0")
    }

    private static func isDrinkItem(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower.contains("alcohol-free")
            || lower.contains("alcohol free")
            || lower.contains("non-alcoholic")
            || lower.contains("non alcoholic") {
            return true
        }
        return containsBeerWord(lower)
    }

    private static func containsBeerWord(_ lower: String) -> Bool {
        lower.range(of: #"\b(lagers?|beers?|ales?|stouts?)\b"#, options: .regularExpression) != nil
    }

    private static func mentionsDrink(_ description: String?) -> Bool {
        guard let description else { return false }
        let lower = description.lowercased()
        if lower.contains("alcohol-free")
            || lower.contains("alcohol free")
            || lower.contains("non-alcoholic")
            || lower.contains("non alcoholic") {
            return true
        }
        return containsBeerWord(lower)
    }

    private static func hasOtherFood(in description: String?) -> Bool {
        guard let description else { return false }
        let text = description.lowercased().replacingOccurrences(
            of: #"\b(alcohol[-\s]?free|non[-\s]?alcoholic|lagers?|beers?|ales?|stouts?|pints?)\b"#,
            with: " ",
            options: .regularExpression
        )
        return text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { word in
            let token = String(word)
            if fillerWords.contains(token) { return false }
            if Int(token) != nil { return false }
            return true
        }
    }

    /// Keeps burger (and any other) words. Swaps an alcohol-free drink phrase for the pint name.
    private static func descriptionKeepingOtherFood(_ description: String?, drinkName: String) -> String? {
        guard let description else { return nil }
        let patterns = [
            #"\b(alcohol[-\s]?free|non[-\s]?alcoholic)\s+(lager|beer|ale|stout)s?\b"#,
            #"\b(lager|beer|ale|stout)s?,?\s+(alcohol[-\s]?free|non[-\s]?alcoholic)\b"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(description.startIndex..., in: description)
            guard regex.firstMatch(in: description, options: [], range: range) != nil else { continue }
            return regex.stringByReplacingMatches(
                in: description,
                options: [],
                range: range,
                withTemplate: drinkName
            )
        }
        return description
    }

    private static func quantity(in lower: String) -> Int {
        if lower.contains("four pint") || lower.contains("4 pint") { return 4 }
        if lower.contains("three pint") || lower.contains("3 pint") { return 3 }
        if lower.contains("two pint") || lower.contains("2 pint") { return 2 }
        return 1
    }

    private static let gramsPerPint = 568.0

    private static let fillerWords: Set<String> = [
        "a", "an", "and", "the", "of", "with", "i", "had", "have", "has",
        "some", "my", "me", "just", "for", "to", "on", "in", "it", "plus",
        "one", "two", "three", "four", "five", "x", "g", "ml"
    ]
}
