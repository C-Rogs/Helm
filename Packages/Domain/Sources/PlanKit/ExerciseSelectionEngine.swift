import Foundation

public struct ExerciseSelection: Sendable, Hashable {
    public let exercise: CatalogExercise
    public let rationale: String
    public let evidenceIDs: [String]
    public let score: Double

    public init(exercise: CatalogExercise, rationale: String, evidenceIDs: [String], score: Double) {
        self.exercise = exercise
        self.rationale = rationale
        self.evidenceIDs = evidenceIDs
        self.score = score
    }
}

enum ExerciseSelectionEngine {
    private enum Weights {
        static let effectiveness = 0.50
        static let stretchPositionBias = 0.25
        static let stimulusToFatigue = 0.25
        static let primaryMuscleBonus = 0.05
    }

    static func select(
        for muscle: MuscleGroup,
        catalog: [CatalogExercise],
        excluding excludedExerciseIDs: Set<String>,
        availableEquipment: Set<String>?
    ) -> ExerciseSelection? {
        let candidates = catalog.filter { exercise in
            !excludedExerciseIDs.contains(exercise.exerciseID)
                && isEquipmentAvailable(exercise.equipment, availableEquipment: availableEquipment)
                && exercise.muscleMap.contributions.contains { $0.muscle == muscle }
        }

        guard
            let best = candidates.max(by: { lhs, rhs in
                let lhsScore = score(lhs, for: muscle)
                let rhsScore = score(rhs, for: muscle)
                if lhsScore != rhsScore { return lhsScore < rhsScore }
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.exerciseID > rhs.exerciseID
            })
        else {
            return nil
        }

        let rationalePayload = makeRationale(for: best, muscle: muscle)
        return ExerciseSelection(
            exercise: best,
            rationale: rationalePayload.rationale,
            evidenceIDs: rationalePayload.evidenceIDs,
            score: score(best, for: muscle)
        )
    }

    static func makeRationale(
        for exercise: CatalogExercise,
        muscle: MuscleGroup
    ) -> (rationale: String, evidenceIDs: [String]) {
        if let evidence = exercise.evidence {
            let rationale = String(
                format:
                    "Selected for %@: effectiveness %.0f%%, stretch-position bias %.0f%%, stimulus-to-fatigue %.0f%%.",
                muscle.rawValue,
                evidence.effectiveness * 100,
                evidence.stretchPositionBias * 100,
                evidence.stimulusToFatigue * 100
            )
            return (rationale, evidence.citationIDs)
        }

        return (
            "Best available movement for \(muscle.rawValue) given current constraints.",
            []
        )
    }

    static func isEquipmentAvailable(
        _ equipment: String?,
        availableEquipment: Set<String>?
    ) -> Bool {
        guard let availableEquipment, !availableEquipment.isEmpty else { return true }
        guard let equipment else { return true }

        let normalized = equipment
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized.isEmpty || normalized == "bodyweight" || normalized == "body only" {
            return true
        }
        return availableEquipment.contains(normalized)
    }

    private static func score(_ exercise: CatalogExercise, for muscle: MuscleGroup) -> Double {
        if let evidence = exercise.evidence {
            var total =
                evidence.effectiveness * Weights.effectiveness
                + evidence.stretchPositionBias * Weights.stretchPositionBias
                + evidence.stimulusToFatigue * Weights.stimulusToFatigue
            if isPrimaryTarget(exercise, muscle: muscle) {
                total += Weights.primaryMuscleBonus
            }
            return total
        }

        return 1.0 - (Double(exercise.priority) * 0.01)
    }

    private static func isPrimaryTarget(_ exercise: CatalogExercise, muscle: MuscleGroup) -> Bool {
        guard let primary = exercise.muscleMap.contributions.max(by: { $0.fraction < $1.fraction }) else {
            return false
        }
        return primary.muscle == muscle
    }
}
