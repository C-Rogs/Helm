import Core
import Foundation

/// Formats completed workout sessions for coach context and clipboard export.
public enum WorkoutExportFormatter {
    public static func formatForCoachContext(
        draft: WorkoutSessionDraft,
        displayNames: [String: String]
    ) -> String {
        var lines: [String] = []
        let title = draft.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, !title.isEmpty {
            lines.append(title)
        } else {
            lines.append("Workout \(ISO8601Coding.string(from: draft.startedAt))")
        }

        for exercise in draft.exercises.sorted(by: { $0.displayOrder < $1.displayOrder }) {
            let name = displayNames[exercise.exerciseID] ?? exercise.exerciseID
            let completedSets = exercise.sets.filter { $0.status == .completed }.sorted { $0.setIndex < $1.setIndex }
            guard !completedSets.isEmpty else { continue }

            lines.append("")
            lines.append(name)
            for set in completedSets {
                lines.append("  \(formatSetLine(set))")
            }
        }

        if let notes = draft.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            lines.append("")
            lines.append("Notes: \(notes)")
        }

        return lines.joined(separator: "\n")
    }

    public static func formatForClipboard(
        draft: WorkoutSessionDraft,
        displayNames: [String: String]
    ) -> String {
        """
        Helm workout export - paste into Gemini for verification.

        \(formatForCoachContext(draft: draft, displayNames: displayNames))
        """
    }

    public static func formatPrescriptionForClipboard(
        prescription: SessionPrescription,
        displayNames: [String: String]
    ) -> String {
        """
        Helm prescription export - paste into Gemini for verification.

        \(formatPrescriptionBody(prescription: prescription, displayNames: displayNames))
        """
    }

    public static func formatPrescriptionBody(
        prescription: SessionPrescription,
        displayNames: [String: String]
    ) -> String {
        var lines: [String] = []
        if let title = prescription.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            lines.append(title)
        }
        for exercise in prescription.exercises.sorted(by: { $0.order < $1.order }) {
            let name = displayNames[exercise.exerciseID] ?? exercise.exerciseID
            lines.append("")
            lines.append(name)
            for setLine in formatPrescriptionSetLines(exercise) {
                lines.append("  \(setLine)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func formatPrescriptionSetLines(_ exercise: PrescribedExercise) -> [String] {
        let setCount = max(exercise.targetSets, 1)
        let reps = resolvedTargetReps(for: exercise)
        var lines: [String] = []
        for index in 1...setCount {
            var parts = ["Set \(index):"]
            if let mass = exercise.targetMass, let reps {
                parts.append("\(formatWeightKilograms(mass.kilograms)) kg x \(reps)")
            } else if let reps {
                parts.append("x \(reps)")
            }
            if let rpe = exercise.targetRPE {
                parts.append("@ \(formatRPE(rpe))")
            }
            lines.append(parts.joined(separator: " "))
        }
        return lines
    }

    private static func resolvedTargetReps(for exercise: PrescribedExercise) -> Int? {
        switch (exercise.targetRepMin, exercise.targetRepMax) {
        case let (min?, max?) where min == max:
            return min
        case let (min?, max?):
            return (min + max) / 2
        case let (min?, nil):
            return min
        case let (nil, max?):
            return max
        default:
            return nil
        }
    }

    private static func formatWeightKilograms(_ kilograms: Double) -> String {
        kilograms.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", kilograms)
            : String(format: "%.1f", kilograms)
    }

    private static func formatSetLine(_ set: SetEntryDraft) -> String {
        var parts: [String] = []
        if let mass = set.mass, let reps = set.reps {
            parts.append("\(formatWeightKilograms(mass.kilograms)) kg x \(reps)")
        } else if let reps = set.reps {
            parts.append("x \(reps)")
        }
        if let rpe = set.rpe {
            parts.append("@ RPE \(formatRPE(rpe))")
        }
        if let setType = set.setType != .normal ? set.setType.label : nil {
            parts.append("(\(setType))")
        }
        return parts.isEmpty ? "Set \(set.setIndex + 1)" : parts.joined(separator: " ")
    }

    private static func formatRPE(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}

private extension SetType {
    var label: String {
        switch self {
        case .normal: "working"
        case .warmup: "warmup"
        case .dropSet: "drop"
        case .failure: "failure"
        case .assisted: "assisted"
        case .bodyweight: "bodyweight"
        case .timed: "timed"
        case .distance: "distance"
        }
    }
}
