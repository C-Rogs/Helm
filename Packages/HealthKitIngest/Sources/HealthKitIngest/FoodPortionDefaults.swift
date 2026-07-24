import Core
import Foundation

/// Smart default portion for the add-food flow.
public struct FoodPortionDefaults: Sendable, Equatable {
    public let grams: Double
    public let servingLabel: String?
    /// Packaged foods prefer serving labels; produce defaults to grams.
    public let prefersServingLabel: Bool

    public init(grams: Double, servingLabel: String?, prefersServingLabel: Bool) {
        self.grams = grams
        self.servingLabel = servingLabel
        self.prefersServingLabel = prefersServingLabel
    }
}

public enum FoodPortionDefaultsResolver {
    public static let produceDefaultGrams: Double = 100

    public static func defaults(
        for product: ResolvedFoodProduct,
        storedPreference: FoodPortionPreference?
    ) -> FoodPortionDefaults {
        if let storedPreference {
            return FoodPortionDefaults(
                grams: storedPreference.grams,
                servingLabel: storedPreference.servingLabel,
                prefersServingLabel: prefersServingLabel(for: product, servingLabel: storedPreference.servingLabel)
            )
        }

        if let suggestedGrams = product.suggestedGrams {
            return FoodPortionDefaults(
                grams: suggestedGrams,
                servingLabel: product.servingLabel,
                prefersServingLabel: prefersServingLabel(for: product, servingLabel: product.servingLabel)
            )
        }

        switch product.ref.origin {
        case .openFoodFacts:
            return FoodPortionDefaults(
                grams: produceDefaultGrams,
                servingLabel: product.servingLabel,
                prefersServingLabel: true
            )
        case .cofid, .custom:
            return FoodPortionDefaults(
                grams: produceDefaultGrams,
                servingLabel: nil,
                prefersServingLabel: false
            )
        }
    }

    private static func prefersServingLabel(
        for product: ResolvedFoodProduct,
        servingLabel: String?
    ) -> Bool {
        if product.ref.origin == .openFoodFacts {
            return true
        }
        return servingLabel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}
