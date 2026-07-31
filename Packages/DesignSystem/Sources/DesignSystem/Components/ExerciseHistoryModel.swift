import Foundation

public struct ExercisePreviousSetRow: Sendable, Hashable, Equatable, Identifiable {
    public let id: String
    public let setNumber: Int
    public let setTypeLabel: String
    public let previousLabel: String?
    public let sessionLabel: String?

    public init(
        id: String,
        setNumber: Int,
        setTypeLabel: String,
        previousLabel: String?,
        sessionLabel: String?
    ) {
        self.id = id
        self.setNumber = setNumber
        self.setTypeLabel = setTypeLabel
        self.previousLabel = previousLabel
        self.sessionLabel = sessionLabel
    }
}

public struct ExerciseE1RMHistoryRow: Sendable, Hashable, Equatable, Identifiable {
    public let id: String
    public let sessionLabel: String
    public let e1RMKilograms: Double

    public init(id: String, sessionLabel: String, e1RMKilograms: Double) {
        self.id = id
        self.sessionLabel = sessionLabel
        self.e1RMKilograms = e1RMKilograms
    }
}

public struct ExerciseHistoryModel: Sendable, Hashable, Equatable {
    public let exerciseName: String
    public let currentE1RMKilograms: Double?
    public let previousSets: [ExercisePreviousSetRow]
    public let e1RMHistory: [ExerciseE1RMHistoryRow]

    public init(
        exerciseName: String,
        currentE1RMKilograms: Double?,
        previousSets: [ExercisePreviousSetRow],
        e1RMHistory: [ExerciseE1RMHistoryRow]
    ) {
        self.exerciseName = exerciseName
        self.currentE1RMKilograms = currentE1RMKilograms
        self.previousSets = previousSets
        self.e1RMHistory = e1RMHistory
    }
}

public enum ExerciseHistorySnapshot {
    public static func text(for model: ExerciseHistoryModel) -> String {
        var lines = [
            "# Exercise history",
            "## Exercise",
            model.exerciseName,
            "## Current e1RM",
            format(model.currentE1RMKilograms),
            "## PREV"
        ]

        if model.previousSets.isEmpty {
            lines.append("- none")
        } else {
            for row in model.previousSets {
                let prev = row.previousLabel ?? "nil"
                let session = row.sessionLabel ?? "nil"
                lines.append(
                    "- set \(row.setNumber) (\(row.setTypeLabel)): PREV=\(prev) | session=\(session)"
                )
            }
        }

        lines.append("## e1RM history")
        if model.e1RMHistory.isEmpty {
            lines.append("- none")
        } else {
            for row in model.e1RMHistory {
                lines.append("- \(row.sessionLabel): e1RM=\(format(row.e1RMKilograms))")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func format(_ value: Double?) -> String {
        guard let value else { return "nil" }
        return String(format: "%.1f", value)
    }
}
