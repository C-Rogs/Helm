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
        familiarExerciseIDs: Set<String> = []
    ) -> ExerciseSelection? {
        let weights = Weights.forBias(selectionBias)
        let candidates = catalog.filter { exercise in
            !excludedExerciseIDs.contains(exercise.exerciseID)
                && isEquipmentAvailable(exercise.equipment, availableEquipment: availableEquipment)
                && exercise.muscleMap.contributions.contains { $0.muscle == muscle }
        }

        guard
            let best = candidates.max(by: { lhs, rhs in
                let lhsScore = score(lhs, for: muscle, slot: nil, weights: weights, familiarExerciseIDs: familiarExerciseIDs)
                let rhsScore = score(rhs, for: muscle, slot: nil, weights: weights, familiarExerciseIDs: familiarExerciseIDs)
                if lhsScore != rhsScore { return lhsScore < rhsScore }
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.exerciseID > rhs.exerciseID
            })
        else {
            return nil
        }

        let rationalePayload = makeRationale(for: best, muscle: muscle, slot: nil)
        return ExerciseSelection(
            exercise: best,
            rationale: rationalePayload.rationale,
            evidenceIDs: rationalePayload.evidenceIDs,
            score: score(best, for: muscle, slot: nil, weights: weights, familiarExerciseIDs: familiarExerciseIDs)
        )
    }

    static func select(
        for slot: PatternSlot,
        catalog: [CatalogExercise],
        excluding excludedExerciseIDs: Set<String>,
        availableEquipment: Set<String>?,
        selectionBias: MethodologyPreferences.SelectionBias = .balanced,
        familiarExerciseIDs: Set<String> = []
    ) -> ExerciseSelection? {
        let weights = Weights.forBias(selectionBias)
        let muscle = slot.primaryMuscle
        let candidates = catalog.filter { exercise in
            !excludedExerciseIDs.contains(exercise.exerciseID)
                && isEquipmentAvailable(exercise.equipment, availableEquipment: availableEquipment)
                && exercise.muscleMap.contributions.contains { $0.muscle == muscle }
        }

        let preferredClassMatches = candidates.filter { exercise in
            SlotClassFit.matchesPreferredClass(exercise, slot: slot)
        }
        let untypedKeywordHits = candidates.filter { exercise in
            let untyped = exercise.movementClass == nil || exercise.movementClass == .other
            return untyped
                && MovementPatternMatcher.patternScore(
                    exerciseID: exercise.exerciseID,
                    pattern: slot.pattern
                ) > 0
        }
        let patterned = candidates.filter {
            MovementPatternMatcher.patternScore(exerciseID: $0.exerciseID, pattern: slot.pattern) > 0
        }
        let pool: [CatalogExercise]
        if !preferredClassMatches.isEmpty {
            pool = preferredClassMatches
        } else if !untypedKeywordHits.isEmpty {
            pool = untypedKeywordHits
        } else if !patterned.isEmpty {
            pool = patterned
        } else {
            pool = candidates.filter {
                MovementPatternMatcher.softMuscleFallback(exercise: $0, slot: slot)
            }
        }

        let openerPool = applyOpenerPolicy(slot: slot, pool: pool, candidates: candidates)

        guard
            let best = openerPool.max(by: { lhs, rhs in
                let lhsScore = score(
                    lhs,
                    for: muscle,
                    slot: slot,
                    weights: weights,
                    familiarExerciseIDs: familiarExerciseIDs
                )
                let rhsScore = score(
                    rhs,
                    for: muscle,
                    slot: slot,
                    weights: weights,
                    familiarExerciseIDs: familiarExerciseIDs
                )
                if lhsScore != rhsScore { return lhsScore < rhsScore }
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.exerciseID > rhs.exerciseID
            })
        else {
            return nil
        }

        let rationalePayload = makeRationale(for: best, muscle: muscle, slot: slot)
        return ExerciseSelection(
            exercise: best,
            rationale: rationalePayload.rationale,
            evidenceIDs: rationalePayload.evidenceIDs,
            score: score(
                best,
                for: muscle,
                slot: slot,
                weights: weights,
                familiarExerciseIDs: familiarExerciseIDs
            )
        )
    }

    static func makeRationale(
        for exercise: CatalogExercise,
        muscle: MuscleGroup,
        slot: PatternSlot? = nil
    ) -> (rationale: String, evidenceIDs: [String]) {
        if let evidence = exercise.evidence {
            let patternNote = slot.map { " (\($0.pattern.rawValue) slot)" } ?? ""
            let rationale = String(
                format:
                    "Selected for %@%@: effectiveness %.0f%%, stretch-position bias %.0f%%, stimulus-to-fatigue %.0f%%.",
                muscle.rawValue,
                patternNote,
                evidence.effectiveness * 100,
                evidence.stretchPositionBias * 100,
                evidence.stimulusToFatigue * 100
            )
            return (rationale, evidence.citationIDs)
        }

        if let slot {
            return (
                "Best available \(slot.pattern.rawValue) movement for \(muscle.rawValue).",
                []
            )
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
        slot: PatternSlot? = nil,
        weights: Weights,
        familiarExerciseIDs: Set<String>
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

        if let slot {
            total += SlotClassFit.classScore(exercise, slot: slot)
            total += SlotClassFit.loadabilityScore(exercise, slot: slot)
            total += MovementPatternMatcher.patternScore(
                exerciseID: exercise.exerciseID,
                pattern: slot.pattern
            ) * 0.35
        }

        if familiarExerciseIDs.contains(exercise.exerciseID) {
            total += 0.25
        }
        if exercise.evidence == nil, exercise.priority == 0 {
            total += 0.15
        }
        return total
    }

    /// Slot 0 compound overloads skip isolation and unloaded bodyweight when a loadable option exists.
    private static func applyOpenerPolicy(
        slot: PatternSlot,
        pool: [CatalogExercise],
        candidates: [CatalogExercise]
    ) -> [CatalogExercise] {
        guard slot.index == 0, slot.role == .primary, SlotClassFit.isCompoundOverload(slot.pattern) else {
            return pool
        }
        func isOpenerEligible(_ exercise: CatalogExercise) -> Bool {
            exercise.movementClass != .isolation
                && SlotClassFit.isProgressivelyLoadable(exercise.equipment)
        }
        let fromPool = pool.filter(isOpenerEligible)
        if !fromPool.isEmpty { return fromPool }
        let fromPreferred = candidates.filter {
            SlotClassFit.matchesPreferredClass($0, slot: slot) && isOpenerEligible($0)
        }
        if !fromPreferred.isEmpty { return fromPreferred }
        return pool
    }

    private static func isPrimaryTarget(_ exercise: CatalogExercise, muscle: MuscleGroup) -> Bool {
        guard let primary = exercise.muscleMap.contributions.max(by: { $0.fraction < $1.fraction }) else {
            return false
        }
        return primary.muscle == muscle
    }
}
