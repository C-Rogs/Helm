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
    /// Preferred stepper ceiling. The live value may be higher so an out-of-range
    /// count can still be reduced without trapping SwiftUI's Stepper.
    public static let preferredQuantityMax = 24
    public static let quantityHardCap = 99

    public static func clampedQuantity(_ value: Int) -> Int {
        min(max(value, 1), quantityHardCap)
    }

    public static func clampedQuantity(fromDouble value: Double) -> Int {
        guard value.isFinite else { return 1 }
        let rounded = value.rounded()
        if rounded < 1 { return 1 }
        if rounded > Double(quantityHardCap) { return quantityHardCap }
        return Int(rounded)
    }

    public static func quantityStepperRange(for quantity: Int) -> ClosedRange<Int> {
        1 ... max(preferredQuantityMax, clampedQuantity(quantity))
    }

    public static func detect(
        for productName: String,
        suggestedGrams: Double? = nil,
        servingLabel: String? = nil
    ) -> CountablePortionConfig? {
        let normalized = NutritionLookup.normalize(productName)
        let trimmedServing = trimmed(servingLabel)?.lowercased()

        if let trimmedServing, trimmedServing.contains("whole"),
           let grams = positive(suggestedGrams) {
            let unitGrams = unitGramsFromServing(
                suggestedGrams: grams,
                servingLabel: servingLabel,
                fallback: grams
            )
            return CountablePortionConfig(
                kind: .serving,
                sizeOptions: [ProducePortionOption(label: "1 whole", grams: unitGrams)],
                unitNoun: "whole",
                pluralNoun: "whole",
                fixedUnitGrams: unitGrams
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
                fixedUnitGrams: unitGramsFromServing(
                    suggestedGrams: suggestedGrams,
                    servingLabel: servingLabel,
                    fallback: 60
                )
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
                fixedUnitGrams: unitGramsFromServing(
                    suggestedGrams: suggestedGrams,
                    servingLabel: servingLabel,
                    fallback: 30
                )
            )
        }

        if let trimmedServing, let config = detectFromServingLabel(trimmedServing, suggestedGrams: suggestedGrams) {
            return config
        }

        if let serving = trimmedServing, let grams = positive(suggestedGrams),
           isGramStyleServing(serving), !normalized.contains("banana") {
            let unitGrams = unitGramsFromServing(
                suggestedGrams: grams,
                servingLabel: servingLabel,
                fallback: grams
            )
            return CountablePortionConfig(
                kind: .serving,
                sizeOptions: [ProducePortionOption(label: "1 whole", grams: unitGrams)],
                unitNoun: "whole",
                pluralNoun: "whole",
                fixedUnitGrams: unitGrams
            )
        }

        if !normalized.contains("banana"),
           let produce = produceWholeConfig(
            normalized,
            suggestedGrams: suggestedGrams,
            servingLabel: servingLabel
           ) {
            return produce
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
        fallbackGrams: Double,
        quantity: Int = 1
    ) -> Double {
        if let sizeOption {
            return sizeOption.grams
        }
        if let fixed = config.fixedUnitGrams {
            return fixed
        }
        let count = max(quantity, 1)
        if count > 1, fallbackGrams > 0 {
            return fallbackGrams / Double(count)
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

    private static func isGramStyleServing(_ serving: String) -> Bool {
        serving.contains("g")
            || serving.contains("serving")
            || serving.contains("portion")
            || serving.contains("whole")
    }

    private static func produceWholeConfig(
        _ normalized: String,
        suggestedGrams: Double?,
        servingLabel: String?
    ) -> CountablePortionConfig? {
        let keys = ["avocado", "apple", "pear", "orange", "tomato", "potato"]
        guard let key = keys.first(where: { normalized.contains($0) }) else { return nil }
        let sizes = unitSizeOptions(forKeyword: key)
        let catalogGrams = sizes.first { $0.label.localizedCaseInsensitiveContains("medium") }?.grams
            ?? sizes.first?.grams
        let wholeGrams = unitGramsFromServing(
            suggestedGrams: suggestedGrams,
            servingLabel: servingLabel,
            fallback: catalogGrams ?? 0
        )
        guard wholeGrams > 0 else { return nil }
        return CountablePortionConfig(
            kind: .serving,
            sizeOptions: [ProducePortionOption(label: "1 whole", grams: wholeGrams)],
            unitNoun: "whole",
            pluralNoun: "whole",
            fixedUnitGrams: wholeGrams
        )
    }

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
                fixedUnitGrams: unitGramsFromServing(
                    suggestedGrams: suggestedGrams,
                    servingLabel: servingLabel,
                    fallback: 60
                )
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
                fixedUnitGrams: unitGramsFromServing(
                    suggestedGrams: suggestedGrams,
                    servingLabel: servingLabel,
                    fallback: 30
                )
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

    /// Grams for one countable unit. If the serving label already encodes a count
    /// (`34 bars`) and `suggestedGrams` is the current total, divide so re-detect
    /// does not treat the total as one unit (that explosion overflowed `Int`).
    private static func unitGramsFromServing(
        suggestedGrams: Double?,
        servingLabel: String?,
        fallback: Double
    ) -> Double {
        let grams = positive(suggestedGrams) ?? fallback
        guard let label = trimmed(servingLabel), let quantity = leadingQuantity(in: label), quantity > 1 else {
            return grams
        }
        return grams / Double(quantity)
    }

    /// Leading count in labels like `3 large eggs` or `2 bars`.
    /// Gram weights (`35 g`, `60g (1 bar)`) are not portion counts.
    private static func leadingQuantity(in label: String) -> Int? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmed.range(of: #"^\d+(?:\.\d+)?"#, options: .regularExpression) else {
            return nil
        }
        let numberText = String(trimmed[match])
        let rest = trimmed[match.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if rest.range(of: #"^(g|grams?)\b"#, options: .regularExpression) != nil {
            return nil
        }
        guard let value = Double(numberText), value >= 1, value == value.rounded() else {
            return nil
        }
        return Int(value)
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
