import Core
import Foundation

public enum BriefEngineTextComposer {
    public static func compose(from inputs: BriefInputsSnapshot) -> String {
        var sentences: [String] = []

        if let prescription = inputs.prescription {
            var session = "\(prescription.title) today: \(prescription.totalSets) sets across \(prescription.exerciseCount) exercises"
            if prescription.readinessAdjusted {
                session += ", volume trimmed"
            }
            sentences.append(session + ".")
            if let emphasis = prescription.emphasis, !emphasis.isEmpty {
                sentences.append("Emphasis: \(emphasis).")
            }
        } else {
            sentences.append("No session prescribed yet.")
        }

        let nutrition = inputs.nutrition
        sentences.append(
            "Fuel with \(nutrition.caloriesKcal) kcal and \(nutrition.proteinGrams)g protein (\(nutrition.dayType) day)."
        )

        return sentences.joined(separator: " ")
    }
}
