import Core
import Foundation

enum SetLogValidation {
    static let minWeightKg = 0.5
    static let maxWeightKg = 500.0
    static let minReps = 1
    static let maxReps = 50
    static let minRPE = 5.0
    static let maxRPE = 10.0

    static func normalizedNumpadText(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix(".") {
            trimmed.removeLast()
        }
        return trimmed
    }

    static func allowsAppendingDecimal(to text: String) -> Bool {
        !text.contains(".")
    }

    static func validate(field: NumpadFieldKind, text: String) -> String? {
        let trimmed = normalizedNumpadText(text)
        guard !trimmed.isEmpty else { return nil }

        switch field {
        case .weight:
            guard let value = Double(trimmed) else {
                return "Enter a valid weight."
            }
            guard value >= minWeightKg, value <= maxWeightKg else {
                return "Weight must be \(formatKg(minWeightKg))–\(formatKg(maxWeightKg)) kg."
            }
        case .reps:
            guard let value = Int(trimmed) else {
                return "Enter whole reps."
            }
            guard value >= minReps, value <= maxReps else {
                return "Reps must be \(minReps)–\(maxReps)."
            }
        case .rpe:
            guard let value = Double(trimmed) else {
                return "Enter a valid RPE."
            }
            guard value >= minRPE, value <= maxRPE else {
                return "RPE must be \(Int(minRPE))–\(Int(maxRPE))."
            }
        }
        return nil
    }

    private static func formatKg(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}
