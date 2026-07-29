import Core
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
    private struct Weights {
        let effectiveness: Double
        let stretchPositionBias: Double
        let stimulusToFatigue: Double
        let primaryMuscleBonus = 0.05

        static func forBias(_ bias: MethodologyPreferences.SelectionBias) -> Weights {
            switch bias {
            case .balanced:
                Weights(effectiveness: 0.50, stretchPositionBias: 0.25, stimulusToFatigue: 0.25)
            case .stretch:
                Weights(effectiveness: 0.40, stretchPositionBias: 0.40, stimulusToFatigue: 0.20)
            case .stimulusToFatigue:
                Weights(effectiveness: 0.40, stretchPositionBias: 0.20, stimulusToFatigue: 0.40)
            }
        }
    }

    static func select(
        for muscle: MuscleGroup,
        catalog: [CatalogExercise],
        excluding excludedExerciseIDs: Set<String>,
        availableEquipment: Set<String>?,
        selectionBias: MethodologyPreferences.SelectionBias = .balanced,
        familiarExerciseIDs: Set<String> = [],
        emphasisMuscles: Set<MuscleGroup> = []
    ) -> ExerciseSelection? {
        let weights = Weights.forBias(selectionBias)
        let candidates = catalog.filter { exercise in
            !excludedExerciseIDs.contains(exercise.exerciseID)
                && isEquipmentAvailable(exercise.equipment, availableEquipment: availableEquipment)
                && exercise.muscleMap.contributions.contains { $0.muscle == muscle }
        }

        guard
            let best = candidates.max(by: { lhs, rhs in
                let lhsScore = score(
                    lhs,
                    for: muscle,
                    weights: weights,
                    familiarExerciseIDs: familiarExerciseIDs,
                    emphasisMuscles: emphasisMuscles
                )
                let rhsScore = score(
                    rhs,
                    for: muscle,
                    weights: weights,
                    familiarExerciseIDs: familiarExerciseIDs,
                    emphasisMuscles: emphasisMuscles
                )
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
            score: score(
                best,
                for: muscle,
                weights: weights,
                familiarExerciseIDs: familiarExerciseIDs,
                emphasisMuscles: emphasisMuscles
            )
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

    private static func score(
        _ exercise: CatalogExercise,
        for muscle: MuscleGroup,
        weights: Weights,
        familiarExerciseIDs: Set<String>,
        emphasisMuscles: Set<MuscleGroup>
    ) -> Double {
        var total: Double
        if let evidence = exercise.evidence {
            total =
                evidence.effectiveness * weights.effectiveness
                + evidence.stretchPositionBias * weights.stretchPositionBias
                + evidence.stimulusToFatigue * weights.stimulusToFatigue
            if isPrimaryTarget(exercise, muscle: muscle) {
                total += weights.primaryMuscleBonus
            }
        } else {
            total = 1.0 - (Double(exercise.priority) * 0.05)
        }

        if emphasisMuscles.contains(muscle) {
            if isPrimaryTarget(exercise, muscle: muscle) {
                total += 0.20
            }
            if let contribution = exercise.muscleMap.contributions.first(where: { $0.muscle == muscle }) {
                total += contribution.fraction * 0.10
            }
        }

        if familiarExerciseIDs.contains(exercise.exerciseID) {
            total += 0.25
        }
        if exercise.evidence == nil, exercise.priority == 0 {
            total += 0.15
        }
        return total
    }

    private static func isPrimaryTarget(_ exercise: CatalogExercise, muscle: MuscleGroup) -> Bool {
        guard let primary = exercise.muscleMap.contributions.max(by: { $0.fraction < $1.fraction }) else {
            return false
        }
        return primary.muscle == muscle
    }
}
