import Foundation

public enum CountableUnitKind: String, Sendable, Equatable {
    case egg
    case bar
    case pot
    case scoop
    case serving
}

/// Configuration for count-based portion entry (size + quantity stepper).
public struct CountablePortionConfig: Sendable, Equatable {
    public let kind: CountableUnitKind
    public let sizeOptions: [ProducePortionOption]
    public let unitNoun: String
    public let pluralNoun: String
    /// Fixed grams per unit when there are no size variants (e.g. branded bar).
    public let fixedUnitGrams: Double?

    public init(
        kind: CountableUnitKind,
        sizeOptions: [ProducePortionOption],
        unitNoun: String,
        pluralNoun: String,
        fixedUnitGrams: Double? = nil
    ) {
        self.kind = kind
        self.sizeOptions = sizeOptions
        self.unitNoun = unitNoun
        self.pluralNoun = pluralNoun
        self.fixedUnitGrams = fixedUnitGrams
    }

    public var hasSizeVariants: Bool {
        sizeOptions.count > 1
    }
}

public enum PortionInputMode: Sendable, Equatable {
    case countable(CountablePortionConfig)
    case weight
}

public enum CountablePortion {
    public static func detect(
        for productName: String,
        suggestedGrams: Double? = nil,
        servingLabel: String? = nil
    ) -> CountablePortionConfig? {
        let normalized = NutritionLookup.normalize(productName)
        let trimmedServing = trimmed(servingLabel)?.lowercased()

        if let trimmedServing, trimmedServing.contains("whole"),
           let grams = positive(suggestedGrams) {
            return CountablePortionConfig(
                kind: .serving,
                sizeOptions: [ProducePortionOption(label: "1 whole", grams: grams)],
                unitNoun: "whole",
                pluralNoun: "whole",
                fixedUnitGrams: grams
            )
        }

        if normalized.contains("egg") {
            return CountablePortionConfig(
                kind: .egg,
                sizeOptions: unitSizeOptions(forKeyword: "egg"),
                unitNoun: "egg",
                pluralNoun: "eggs"
            )
        }

        if normalized.contains("bar") || trimmedServing?.contains("bar") == true {
            return CountablePortionConfig(
                kind: .bar,
                sizeOptions: [],
                unitNoun: "bar",
                pluralNoun: "bars",
                fixedUnitGrams: positive(suggestedGrams) ?? 60
            )
        }

        if normalized.contains("yogurt") || normalized.contains("yoghurt") {
            return CountablePortionConfig(
                kind: .pot,
                sizeOptions: [
                    ProducePortionOption(label: "1 small pot", grams: 125),
                    ProducePortionOption(label: "1 pot", grams: 170)
                ],
                unitNoun: "pot",
                pluralNoun: "pots"
            )
        }

        if normalized.contains("scoop") || trimmedServing?.contains("scoop") == true {
            return CountablePortionConfig(
                kind: .scoop,
                sizeOptions: [],
                unitNoun: "scoop",
                pluralNoun: "scoops",
                fixedUnitGrams: positive(suggestedGrams) ?? 30
            )
        }

        if let trimmedServing, let config = detectFromServingLabel(trimmedServing, suggestedGrams: suggestedGrams) {
            return config
        }

        return nil
    }

    public static func formatServingLabel(
        quantity: Int,
        sizeLabel: String?,
        config: CountablePortionConfig
    ) -> String {
        let count = max(quantity, 1)
        let noun = count == 1 ? config.unitNoun : config.pluralNoun

        if let sizeLabel, config.hasSizeVariants {
            let descriptor = sizeDescriptor(from: sizeLabel)
            if descriptor.isEmpty {
                return "\(count) \(noun)"
            }
            return "\(count) \(descriptor) \(noun)"
        }

        return "\(count) \(noun)"
    }

    public static func parseServingLabel(
        _ label: String,
        config: CountablePortionConfig
    ) -> (quantity: Int, sizeOption: ProducePortionOption?)? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let quantity = leadingQuantity(in: trimmed) ?? 1

        if config.hasSizeVariants {
            if let match = config.sizeOptions.first(where: { option in
                trimmed.localizedCaseInsensitiveContains(sizeDescriptor(from: option.label))
            }) {
                return (quantity, match)
            }
            if let inferred = inferDefaultSize(from: trimmed, config: config) {
                return (quantity, inferred)
            }
        }

        return (quantity, config.sizeOptions.first)
    }

    public static func inferDefaultSize(
        from productName: String,
        config: CountablePortionConfig
    ) -> ProducePortionOption? {
        guard config.hasSizeVariants else {
            if let fixed = config.fixedUnitGrams {
                return ProducePortionOption(label: "1 \(config.unitNoun)", grams: fixed)
            }
            return config.sizeOptions.first
        }

        let normalized = NutritionLookup.normalize(productName)
        if normalized.contains("small") {
            return config.sizeOptions.first { $0.label.localizedCaseInsensitiveContains("small") }
        }
        if normalized.contains("medium") {
            return config.sizeOptions.first { $0.label.localizedCaseInsensitiveContains("medium") }
        }
        if normalized.contains("large") {
            return config.sizeOptions.first { $0.label.localizedCaseInsensitiveContains("large") }
        }

        return config.sizeOptions.first { $0.label.localizedCaseInsensitiveContains("medium") }
            ?? config.sizeOptions.first
    }

    public static func gramsPerUnit(
        sizeOption: ProducePortionOption?,
        config: CountablePortionConfig,
        fallbackGrams: Double
    ) -> Double {
        if let sizeOption {
            return sizeOption.grams
        }
        if let fixed = config.fixedUnitGrams {
            return fixed
        }
        return fallbackGrams
    }

    public static func isLikelyPackWeight(_ grams: Double, config: CountablePortionConfig) -> Bool {
        let defaultSize = config.sizeOptions.first { $0.label.localizedCaseInsensitiveContains("medium") }
            ?? config.sizeOptions.first
        let unitGrams = gramsPerUnit(
            sizeOption: defaultSize,
            config: config,
            fallbackGrams: grams
        )
        guard unitGrams > 0 else { return false }
        return grams > unitGrams * 2.5
    }

    // MARK: - Private

    private static func detectFromServingLabel(
        _ servingLabel: String,
        suggestedGrams: Double?
    ) -> CountablePortionConfig? {
        if servingLabel.contains("bar") {
            return CountablePortionConfig(
                kind: .bar,
                sizeOptions: [],
                unitNoun: "bar",
                pluralNoun: "bars",
                fixedUnitGrams: positive(suggestedGrams) ?? 60
            )
        }
        if servingLabel.contains("pot") {
            return CountablePortionConfig(
                kind: .pot,
                sizeOptions: [
                    ProducePortionOption(label: "1 small pot", grams: 125),
                    ProducePortionOption(label: "1 pot", grams: 170)
                ],
                unitNoun: "pot",
                pluralNoun: "pots"
            )
        }
        if servingLabel.contains("scoop") {
            return CountablePortionConfig(
                kind: .scoop,
                sizeOptions: [],
                unitNoun: "scoop",
                pluralNoun: "scoops",
                fixedUnitGrams: positive(suggestedGrams) ?? 30
            )
        }
        return nil
    }

    private static func unitSizeOptions(forKeyword keyword: String) -> [ProducePortionOption] {
        PortionOptionCatalog.unitSizeOptions(forKeyword: keyword)
    }

    private static func sizeDescriptor(from label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if let match = trimmed.range(of: #"^\d+\s+"#, options: .regularExpression) {
            return String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private static func leadingQuantity(in label: String) -> Int? {
        guard let match = label.range(of: #"^(\d+)"#, options: .regularExpression) else { return nil }
        let digits = String(label[match])
        return Int(digits)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }
}
