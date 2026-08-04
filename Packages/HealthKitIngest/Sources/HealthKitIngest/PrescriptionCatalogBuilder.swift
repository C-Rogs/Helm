import Core
import Foundation
import PlanKit

/// Maps persisted exercise rows into PlanKit catalog entries.
enum PrescriptionCatalogBuilder {
    static func build(
        from rows: [ExerciseCatalogRow],
        familiarExerciseIDs: Set<String> = []
    ) -> [CatalogExercise] {
        rows.compactMap { row in
            guard let muscleMap = muscleMap(for: row) else { return nil }
            let priority: Int
            if row.isPickerDefault {
                priority = 0
            } else if familiarExerciseIDs.contains(row.id) {
                priority = -1
            } else {
                priority = 1
            }
            return CatalogExercise(
                exerciseID: row.id,
                muscleMap: muscleMap,
                priority: priority,
                equipment: normalizedEquipment(row.equipment)
            )
        }
    }

    private static func muscleMap(for row: ExerciseCatalogRow) -> ExerciseMuscleMap? {
        var contributions: [ExerciseMuscleContribution] = []
        if let primary = row.primaryMuscleGroup, let muscle = mapMuscle(primary) {
            contributions.append(ExerciseMuscleContribution(
                muscle: muscle,
                fraction: 1.0,
                tier: .primary
            ))
        }
        let secondaryMuscles = row.secondaryMuscleGroups.compactMap(mapMuscle)
        if secondaryMuscles.isEmpty, contributions.isEmpty {
            return nil
        }
        if secondaryMuscles.isEmpty {
            return ExerciseMuscleMap(exerciseID: row.id, contributions: contributions)
        }

        for (index, muscle) in secondaryMuscles.enumerated() {
            let tier: MuscleContributionTier = index == 0 ? .majorSynergist : .minorSynergist
            contributions.append(ExerciseMuscleContribution(
                muscle: muscle,
                fraction: tier.credit,
                tier: tier
            ))
        }
        normalizeContributions(&contributions)
        return ExerciseMuscleMap(exerciseID: row.id, contributions: contributions)
    }

    private static func normalizeContributions(_ contributions: inout [ExerciseMuscleContribution]) {
        let total = contributions.reduce(0.0) { $0 + $1.fraction }
        guard total > 0 else { return }
        contributions = contributions.map {
            ExerciseMuscleContribution(
                muscle: $0.muscle,
                fraction: $0.fraction / total,
                tier: $0.tier
            )
        }
    }

    private static func mapMuscle(_ slug: String) -> MuscleGroup? {
        switch slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "chest": .chest
        case "shoulders": .shoulders
        case "biceps": .biceps
        case "triceps": .triceps
        case "quadriceps", "quads": .quads
        case "hamstrings": .hamstrings
        case "glutes": .glutes
        case "calves": .calves
        case "abs", "abdominals": .abs
        case "lats", "upper back", "middle back", "traps", "lower back", "back": .back
        default: nil
        }
    }

    private static func normalizedEquipment(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        switch normalized {
        case "body only", "bodyweight": return "bodyweight"
        case "e-z curl bar": return "barbell"
        case "kettlebells": return "kettlebell"
        case "bands": return "band"
        default: return normalized
        }
    }
}
