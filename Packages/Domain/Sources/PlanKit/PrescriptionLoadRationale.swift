import Core
import Foundation

/// Formats engine-grounded per-lift load decisions for coach context.
public enum PrescriptionLoadRationale {
    public struct ExerciseInput: Sendable, Equatable {
        public let exerciseID: String
        public let displayName: String
        public let progression: LiftProgression
        public let constraintAffected: Bool

        public init(
            exerciseID: String,
            displayName: String,
            progression: LiftProgression,
            constraintAffected: Bool
        ) {
            self.exerciseID = exerciseID
            self.displayName = displayName
            self.progression = progression
            self.constraintAffected = constraintAffected
        }
    }

    /// One line per exercise: load_decision, last vs prescribed kg, constraint_affected.
    public static func format(exercises: [ExerciseInput]) -> String {
        guard !exercises.isEmpty else { return "" }
        var lines = [
            "Per-lift working-weight decisions from ProgressionEngine.",
            "Cite load_decision only. Never blame standing constraints unless constraint_affected=true.",
            "readiness_adjusted trims set count / RPE, not these loads."
        ]
        for exercise in exercises {
            lines.append(line(for: exercise))
        }
        return lines.joined(separator: "\n")
    }

    public static func constraintAffected(
        exerciseID: String,
        excludedPatterns: Set<MovementPatternKind>
    ) -> Bool {
        excludedPatterns.contains { pattern in
            MovementPatternMatcher.patternScore(exerciseID: exerciseID, pattern: pattern) > 0
        }
    }

    private static func line(for exercise: ExerciseInput) -> String {
        let progression = exercise.progression
        let last = progression.lastSessionWeight.map { formatKg($0.kilograms) } ?? "none"
        let prescribed = progression.workingWeight.map { formatKg($0.kilograms) } ?? "none"
        let kind = ProgressionEngine.liftKind(exerciseID: exercise.exerciseID, muscleMap: nil)
        let increment = formatKg(kind.loadIncrement.stepKilograms)
        return [
            "exercise=\(exercise.displayName)",
            "exercise_id=\(exercise.exerciseID)",
            "load_decision=\(progression.loadDecision.rawValue)",
            "last_session_kg=\(last)",
            "prescribed_kg=\(prescribed)",
            "prescribed_reps=\(progression.targetRepMin)",
            "scheme=\(progression.schemeRepMin)-\(progression.schemeRepMax)",
            "increment_kg=\(increment)",
            "is_stalled_backoff=\(progression.isStalledBackoff)",
            "constraint_affected=\(exercise.constraintAffected)"
        ].joined(separator: " ")
    }

    private static func formatKg(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}
