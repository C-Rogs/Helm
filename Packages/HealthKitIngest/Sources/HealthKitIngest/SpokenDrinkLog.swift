import CoachLLM
import Foundation

/// Corrects a dictated drink when the model picks an alcohol-free row or the wrong count.
public enum SpokenDrinkLog {
    public static func corrected(_ payload: FoodLogPayload, spoken: String) -> FoodLogPayload {
        guard payload.action == .log, let match = match(in: spoken) else { return payload }
        let macros = match.preset.macros(quantity: match.quantity)
        let name = match.quantity == 1
            ? match.preset.displayName
            : "\(match.quantity) × \(match.preset.displayName)"
        return FoodLogPayload(
            schemaVersion: payload.schemaVersion,
            reply: payload.reply,
            action: .log,
            mealID: payload.mealID,
            description: name,
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

    static func match(in spoken: String) -> (preset: AlcoholDrinkPreset, quantity: Int)? {
        let lower = spoken.lowercased()
        if lower.contains("alcohol-free")
            || lower.contains("alcohol free")
            || lower.contains("non-alcoholic")
            || lower.contains("non alcoholic")
            || lower.contains("0.0") {
            return nil
        }
        guard lower.contains("pint") else { return nil }
        guard lower.contains("lager")
            || lower.contains("beer")
            || lower.contains("ale")
            || lower.contains("stout") else { return nil }
        return (.beerPint, quantity(in: lower))
    }

    private static func quantity(in lower: String) -> Int {
        if lower.contains("four pint") || lower.contains("4 pint") { return 4 }
        if lower.contains("three pint") || lower.contains("3 pint") { return 3 }
        if lower.contains("two pint") || lower.contains("2 pint") { return 2 }
        return 1
    }
}
