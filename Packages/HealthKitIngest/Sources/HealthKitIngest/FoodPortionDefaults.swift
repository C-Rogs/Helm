import Core
import Foundation
import NutritionKit

/// Smart default portion for the add-food flow.
public struct FoodPortionDefaults: Sendable, Equatable {
    public let grams: Double
    public let servingLabel: String?
    /// Packaged foods prefer serving labels; produce defaults to grams.
    public let prefersServingLabel: Bool
    public let inputMode: PortionInputMode
    public let defaultQuantity: Int
    public let defaultSizeLabel: String?

    public init(
        grams: Double,
        servingLabel: String?,
        prefersServingLabel: Bool,
        inputMode: PortionInputMode = .weight,
        defaultQuantity: Int = 1,
        defaultSizeLabel: String? = nil
    ) {
        self.grams = grams
        self.servingLabel = servingLabel
        self.prefersServingLabel = prefersServingLabel
        self.inputMode = inputMode
        self.defaultQuantity = CountablePortion.clampedQuantity(defaultQuantity)
        self.defaultSizeLabel = defaultSizeLabel
    }
}

public enum FoodPortionDefaultsResolver {
    public static let produceDefaultGrams: Double = 100

    /// Scan and search always land on the portion step (1 whole / serving chips).
    public static func shouldSkipPortionStep(for _: ResolvedFoodProduct) -> Bool {
        false
    }

    public static func defaults(
        for product: ResolvedFoodProduct,
        storedPreference: FoodPortionPreference?
    ) -> FoodPortionDefaults {
        let countableConfig = CountablePortion.detect(
            for: product.ref.displayName,
            suggestedGrams: product.suggestedGrams,
            servingLabel: product.servingLabel
        )

        if let storedPreference {
            return buildDefaults(
                product: product,
                grams: storedPreference.grams,
                servingLabel: storedPreference.servingLabel,
                countableConfig: countableConfig
            )
        }

        if let suggestedGrams = product.suggestedGrams {
            let adjustedGrams = adjustedSuggestedGrams(
                suggestedGrams,
                product: product,
                countableConfig: countableConfig
            )
            return buildDefaults(
                product: product,
                grams: adjustedGrams,
                servingLabel: product.servingLabel,
                countableConfig: countableConfig
            )
        }

        switch product.ref.origin {
        case .openFoodFacts:
            return buildDefaults(
                product: product,
                grams: produceDefaultGrams,
                servingLabel: product.servingLabel,
                countableConfig: countableConfig
            )
        case .cofid, .custom:
            let portionOptions = PortionOptionCatalog.options(
                for: product.ref.displayName,
                cofidID: product.ref.origin == .cofid ? product.ref.externalID : nil,
                origin: .cofid,
                defaultGrams: produceDefaultGrams
            )
            let medium = portionOptions.first { $0.label == "1 medium" }
                ?? portionOptions.first { $0.label == "1 whole" }
                ?? portionOptions.first { !$0.label.hasSuffix(" g") }
                ?? portionOptions.first
            let resolvedCountable = CountablePortion.detect(
                for: product.ref.displayName,
                suggestedGrams: product.suggestedGrams ?? medium?.grams,
                servingLabel: product.servingLabel ?? medium?.label
            )
            return buildDefaults(
                product: product,
                grams: medium?.grams ?? produceDefaultGrams,
                servingLabel: medium?.label,
                countableConfig: resolvedCountable
            )
        }
    }

    // MARK: - Private

    private static func buildDefaults(
        product: ResolvedFoodProduct,
        grams: Double,
        servingLabel: String?,
        countableConfig: CountablePortionConfig?
    ) -> FoodPortionDefaults {
        guard let config = countableConfig else {
            return FoodPortionDefaults(
                grams: grams,
                servingLabel: servingLabel,
                prefersServingLabel: prefersServingLabel(for: product, servingLabel: servingLabel)
            )
        }

        let parsed = servingLabel.flatMap { CountablePortion.parseServingLabel($0, config: config) }
        let defaultSize = parsed?.sizeOption
            ?? CountablePortion.inferDefaultSize(from: product.ref.displayName, config: config)
        let unitGrams = CountablePortion.gramsPerUnit(
            sizeOption: defaultSize,
            config: config,
            fallbackGrams: grams
        )
        let quantity = CountablePortion.clampedQuantity(
            parsed?.quantity ?? inferredQuantity(from: grams, unitGrams: unitGrams)
        )
        let resolvedGrams = unitGrams * Double(quantity)
        let label = CountablePortion.formatServingLabel(
            quantity: quantity,
            sizeLabel: defaultSize?.label,
            config: config
        )

        return FoodPortionDefaults(
            grams: resolvedGrams,
            servingLabel: label,
            prefersServingLabel: true,
            inputMode: .countable(config),
            defaultQuantity: quantity,
            defaultSizeLabel: defaultSize?.label
        )
    }

    private static func adjustedSuggestedGrams(
        _ suggestedGrams: Double,
        product: ResolvedFoodProduct,
        countableConfig: CountablePortionConfig?
    ) -> Double {
        guard let config = countableConfig else { return suggestedGrams }
        guard CountablePortion.isLikelyPackWeight(suggestedGrams, config: config) else { return suggestedGrams }

        let defaultSize = CountablePortion.inferDefaultSize(from: product.ref.displayName, config: config)
        return CountablePortion.gramsPerUnit(
            sizeOption: defaultSize,
            config: config,
            fallbackGrams: suggestedGrams
        )
    }

    private static func inferredQuantity(from grams: Double, unitGrams: Double) -> Int {
        guard unitGrams > 0 else { return 1 }
        let raw = (grams / unitGrams).rounded()
        return CountablePortion.clampedQuantity(fromDouble: raw)
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
