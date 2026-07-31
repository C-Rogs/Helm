import Core
import DesignSystem
import Foundation
import Persistence

enum ExerciseHistoryBuilder {
    static func build(
        exercise: WorkoutSessionExerciseDraft,
        displayName: String,
        previousLookup: (SetEntryDraft) -> PreviousPerformance?,
        store: PersistenceStore,
        excludingSessionID: String?,
        calendar: Calendar = .current
    ) throws -> ExerciseHistoryModel {
        let previousSets = exercise.sets.enumerated().map { index, set in
            let previous = previousLookup(set)
            return ExercisePreviousSetRow(
                id: set.id,
                setNumber: index + 1,
                setTypeLabel: set.setType.loggerAbbreviation ?? "\(index + 1)",
                previousLabel: previous.map(previousPerformanceLabel),
                sessionLabel: previous.map { sessionLabel(for: $0.completedAt, calendar: calendar) }
            )
        }

        let history = try store.workoutSessions.fetchE1RMHistory(
            exerciseID: exercise.exerciseID,
            limit: 12,
            calendar: calendar
        )
        let e1RMRows = history.enumerated().map { index, point in
            ExerciseE1RMHistoryRow(
                id: "e1rm-\(index)",
                sessionLabel: sessionLabel(for: point.helmDay, calendar: calendar),
                e1RMKilograms: point.e1RMKilograms
            )
        }

        let currentE1RM = try store.workoutSessions.estimatedOneRM(
            exerciseID: exercise.exerciseID,
            excludingSessionID: excludingSessionID
        )?.kilograms ?? history.first?.e1RMKilograms

        return ExerciseHistoryModel(
            exerciseName: displayName,
            currentE1RMKilograms: currentE1RM,
            previousSets: previousSets,
            e1RMHistory: e1RMRows
        )
    }

    private static func previousPerformanceLabel(_ previous: PreviousPerformance) -> String {
        let weight = previous.mass.map { formatWeight($0.kilograms) } ?? "-"
        let reps = previous.reps.map(String.init) ?? "-"
        return "\(weight)×\(reps)"
    }

    private static func formatWeight(_ kilograms: Double) -> String {
        kilograms.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", kilograms)
            : String(format: "%.1f", kilograms)
    }

    private static func sessionLabel(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private static func sessionLabel(for helmDay: HelmDay, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        guard let date = calendar.date(from: helmDay.dateComponents()) else {
            return "\(helmDay.month)/\(helmDay.day)"
        }
        return formatter.string(from: date)
    }
}
