import Foundation

/// MFP-style diary row formatting: food eaten as title, portion/weight/brand as detail.
public enum FoodLogDisplayFormatter {
    public static func primaryTitle(displayName: String, servingLabel: String?) -> String {
        if let config = CountablePortion.detect(for: displayName, servingLabel: servingLabel) {
            switch config.kind {
            case .egg:
                return titleNoun(for: config)
            case .bar, .pot, .scoop, .serving:
                let cleaned = stripPackNoise(from: displayName)
                return cleaned.isEmpty ? titleNoun(for: config) : cleaned
            }
        }

        let stripped = stripPackNoise(from: stripBrandPrefix(from: displayName))
        if stripped.isEmpty {
            return displayName
        }
        return stripped
    }

    public static func secondaryDetail(
        displayName: String,
        servingLabel: String?,
        grams: Double
    ) -> String {
        var parts: [String] = []

        if let serving = trimmed(servingLabel), !servingEqualsProductName(serving, displayName: displayName) {
            parts.append(serving)
        }

        if grams > 0 {
            parts.append("\(formatNumber(grams)) g")
        }

        if let brand = parseBrand(from: displayName) {
            parts.append(brand)
        }

        if parts.isEmpty {
            return "\(formatNumber(grams)) g"
        }
        return parts.joined(separator: " · ")
    }

    public static func parseBrand(from displayName: String) -> String? {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let spaceIndex = trimmed.firstIndex(of: " ") else { return nil }

        let first = String(trimmed[..<spaceIndex])
            .trimmingCharacters(in: CharacterSet(charactersIn: ","))
        guard !first.isEmpty, first.rangeOfCharacter(from: .decimalDigits) == nil else { return nil }

        let remainder = String(trimmed[trimmed.index(after: spaceIndex)...])
        guard !remainder.isEmpty else { return nil }

        // Skip generic produce names where the first token is part of the food name.
        let genericPrefixes = ["egg", "banana", "apple", "chicken", "white", "brown", "whole"]
        if genericPrefixes.contains(first.lowercased()) {
            return nil
        }

        return first
    }

    public static func shouldShowMealHeader(
        mealName: String,
        lineItems: [MealLineItemDisplayInput]
    ) -> Bool {
        guard lineItems.count > 1 else { return false }
        return true
    }

    public struct MealLineItemDisplayInput: Sendable, Equatable {
        public let displayName: String
        public let servingLabel: String?
        public let grams: Double

        public init(displayName: String, servingLabel: String?, grams: Double) {
            self.displayName = displayName
            self.servingLabel = servingLabel
            self.grams = grams
        }
    }

    // MARK: - Private

    private static func titleNoun(for config: CountablePortionConfig) -> String {
        config.pluralNoun.prefix(1).uppercased() + config.pluralNoun.dropFirst()
    }

    private static func stripBrandPrefix(from displayName: String) -> String {
        guard let brand = parseBrand(from: displayName) else { return displayName }
        let prefix = "\(brand) "
        if displayName.hasPrefix(prefix) {
            return String(displayName.dropFirst(prefix.count))
        }
        return displayName
    }

    private static func stripPackNoise(from name: String) -> String {
        var result = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if let match = result.range(of: #"^\d+\s+"#, options: .regularExpression) {
            result = String(result[match.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        result = result.replacingOccurrences(
            of: #"\b\d+\s*(x|pack|pk|eggs?)\b"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func servingEqualsProductName(_ serving: String, displayName: String) -> Bool {
        serving.caseInsensitiveCompare(displayName) == .orderedSame
    }

    /// Display grams / macros. Never converts non-finite values to `Int` (that traps).
    public static func formatNumber(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let nearest = value.rounded()
        if abs(value - nearest) < 1e-6 {
            guard nearest >= Double(Int.min), nearest <= Double(Int.max) else {
                return String(format: "%.1f", value)
            }
            return String(Int(nearest))
        }
        return String(format: "%.1f", value)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
