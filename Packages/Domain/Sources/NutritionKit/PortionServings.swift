import Foundation

/// MFP-style servings math: a decimal multiplier times a serving-size unit.
public enum PortionServings {
    public static let minimum = 0.01
    public static let maximum = 999.0

    public static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(max(value, minimum), maximum)
    }

    public static func parse(_ text: String) -> Double? {
        let trimmed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(trimmed), value.isFinite, value > 0 else { return nil }
        return clamped(value)
    }

    public static func format(_ value: Double) -> String {
        let clamped = clamped(value)
        if abs(clamped.rounded() - clamped) < 0.000_1 {
            return String(Int(clamped.rounded()))
        }
        let hundredths = (clamped * 100).rounded() / 100
        return String(format: "%g", hundredths)
    }

    public static func totalGrams(servings: Double, unitGrams: Double) -> Double {
        max(clamped(servings) * max(unitGrams, 0), 0)
    }

    public static func servings(grams: Double, unitGrams: Double) -> Double {
        guard unitGrams > 0 else { return 1 }
        return clamped(grams / unitGrams)
    }

    public static func displayLabel(servings: Double, servingSize: String) -> String {
        let size = servingSize.trimmingCharacters(in: .whitespacesAndNewlines)
        if size.isEmpty {
            return format(servings)
        }
        if abs(servings - 1) < 0.000_1 {
            return size
        }
        return "\(format(servings)) x \(size)"
    }
}
