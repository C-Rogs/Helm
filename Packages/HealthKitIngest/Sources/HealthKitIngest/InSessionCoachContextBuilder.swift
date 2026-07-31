import Core
import Foundation
import Persistence

/// Formats active-session state for in-session coach prompts.
public enum InSessionCoachContextBuilder {
    public static func sessionExerciseBlock(
        snapshot: ActiveSessionSnapshot,
        displayNames: [String: String],
        importContextNotes: [String] = []
    ) -> String {
        let sortedExercises = snapshot.session.exercises.sorted { $0.displayOrder < $1.displayOrder }
        var lines: [String] = []

        for (index, exercise) in sortedExercises.enumerated() {
            let label = ExerciseDisplayFormatter.friendlyName(
                for: exercise.exerciseID,
                displayNames: displayNames
            )
            let archetypeID = CoachArchetypeSupport.archetype(for: exercise.exerciseID)?.id ?? exercise.exerciseID
            lines.append("- slot \(index + 1) | \(archetypeID) | \(label)")

            let sortedSets = exercise.sets.sorted { $0.setIndex < $1.setIndex }
            for set in sortedSets {
                lines.append("  \(setLine(set))")
            }
        }

        if !importContextNotes.isEmpty {
            lines.append("")
            lines.append("Import context (non-exercise lines):")
            for note in importContextNotes {
                lines.append("- \(note)")
            }
        }

        return lines.joined(separator: "\n")
    }

    public static func importContextNotes(from notes: String?) -> [String] {
        guard let notes else { return [] }
        return notes
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func setLine(_ set: SetEntryDraft) -> String {
        let status = set.status == .completed ? "completed" : set.status.rawValue
        var parts: [String] = ["set \(set.setIndex + 1) (\(status)):"]

        if let mass = set.mass {
            parts.append(formatMass(mass.kilograms))
        }
        if let reps = set.reps {
            parts.append("x \(reps)")
        }
        if let rpe = set.rpe {
            parts.append("@ RPE \(formatNumber(rpe))")
        }

        if parts.count == 1 {
            parts.append("n/a")
        }

        return parts.joined(separator: " ")
    }

    private static func formatMass(_ kilograms: Double) -> String {
        kilograms.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f kg", kilograms)
            : String(format: "%.1f kg", kilograms)
    }

    private static func formatNumber(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}
