import Core
import Foundation
import Persistence
import PlanKit

/// Maps persisted exercise rows into PlanKit catalog entries.
enum PrescriptionCatalogBuilder {
    static func build(from rows: [ExerciseCatalogRow]) -> [CatalogExercise] {
        rows.compactMap { row in
            guard let muscleMap = muscleMap(for: row) else { return nil }
            return CatalogExercise(
                exerciseID: row.id,
                muscleMap: muscleMap,
                priority: row.isPickerDefault ? 0 : 1,
                equipment: normalizedEquipment(row.equipment)
            )
        }
    }

    private static func muscleMap(for row: ExerciseCatalogRow) -> ExerciseMuscleMap? {
        var contributions: [ExerciseMuscleContribution] = []
        if let primary = row.primaryMuscleGroup, let muscle = mapMuscle(primary) {
            contributions.append(ExerciseMuscleContribution(muscle: muscle, fraction: 0.7))
        }
        let secondaryMuscles = row.secondaryMuscleGroups.compactMap(mapMuscle)
        if secondaryMuscles.isEmpty, contributions.isEmpty {
            return nil
        }
        if secondaryMuscles.isEmpty {
            contributions[0] = ExerciseMuscleContribution(muscle: contributions[0].muscle, fraction: 1.0)
        } else {
            let secondaryFraction = (1.0 - contributions.reduce(0.0) { $0 + $1.fraction }) / Double(secondaryMuscles.count)
            for muscle in secondaryMuscles {
                contributions.append(ExerciseMuscleContribution(muscle: muscle, fraction: max(0.05, secondaryFraction)))
            }
            normalizeContributions(&contributions)
        }
        return ExerciseMuscleMap(exerciseID: row.id, contributions: contributions)
    }

    private static func normalizeContributions(_ contributions: inout [ExerciseMuscleContribution]) {
        let total = contributions.reduce(0.0) { $0 + $1.fraction }
        guard total > 0 else { return }
        contributions = contributions.map {
            ExerciseMuscleContribution(muscle: $0.muscle, fraction: $0.fraction / total)
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
