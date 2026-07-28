import Core
import Foundation

public enum BriefEngineTextComposer {
    public static func compose(from inputs: BriefInputsSnapshot) -> String {
        var sentences: [String] = []

        if let score = inputs.readiness.score {
            var readinessParts = ["ARC \(score)"]
            if let band = inputs.readiness.band {
                readinessParts.append(band)
            }
            if let confidence = inputs.readiness.confidence {
                readinessParts.append("\(confidence) confidence")
            }
            sentences.append(readinessParts.joined(separator: ", ") + ".")
        } else if let validNights = inputs.readiness.validNights {
            sentences.append("Readiness baseline building (\(validNights)/14 nights).")
        } else {
            sentences.append("Readiness data still building.")
        }

        if let prescription = inputs.prescription {
            var session = "Today's session: \(prescription.title)"
            session += " - \(prescription.totalSets) sets across \(prescription.exerciseCount) exercises"
            session += " (\(prescription.phase))"
            if prescription.readinessAdjusted {
                session += ", volume trimmed for readiness"
            }
            if let emphasis = prescription.emphasis, !emphasis.isEmpty {
                session += ", emphasis \(emphasis)"
            }
            sentences.append(session + ".")
        } else {
            sentences.append("No prescribed session yet.")
        }

        let nutrition = inputs.nutrition
        sentences.append(
            "Nutrition targets: \(nutrition.caloriesKcal) kcal, \(nutrition.proteinGrams)g protein, "
                + "\(nutrition.carbohydrateGrams)g carbs, \(nutrition.fatGrams)g fat (\(nutrition.dayType) day)."
        )

        return sentences.joined(separator: " ")
    }
}
