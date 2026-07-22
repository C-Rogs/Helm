import Core
import Foundation
import Persistence
import SwiftUI

enum TrainBootstrap {
    private static let persistence = PersistenceBootstrap.persistenceStore
    private static let engine = ActiveSessionEngine(repository: persistence.activeSessions)

    @MainActor
    static let sideEffects = WorkoutSessionSideEffects(persistence: persistence)

    @MainActor
    static let sessionController = TrainSessionController(
        store: ActiveSessionStore(engine: engine),
        persistence: persistence,
        sideEffects: sideEffects
    )

    @MainActor
    static let historyController = WorkoutHistoryController(persistence: persistence)

    @MainActor
    static let importController = WorkoutImportController(persistence: persistence)

    @MainActor
    static func start() {
        Task {
            await seedPlaceholderExercisesIfNeeded()
            historyController.refresh()
            await sessionController.recover()
        }
    }

    private struct PlaceholderExercise {
        let id: String
        let canonical: String
        let display: String
        let mode: ExerciseMode
        let muscle: String
    }

    private static func seedPlaceholderExercisesIfNeeded() async {
        do {
            guard try persistence.exercises.exerciseCount() == 0 else { return }
            let placeholders: [PlaceholderExercise] = [
                PlaceholderExercise(
                    id: "placeholder-bench-press",
                    canonical: "bench press (barbell)",
                    display: "Bench Press (Barbell)",
                    mode: .weightReps,
                    muscle: "chest"
                ),
                PlaceholderExercise(
                    id: "placeholder-squat",
                    canonical: "squat (barbell)",
                    display: "Squat (Barbell)",
                    mode: .weightReps,
                    muscle: "quads"
                ),
                PlaceholderExercise(
                    id: "placeholder-deadlift",
                    canonical: "deadlift (barbell)",
                    display: "Deadlift (Barbell)",
                    mode: .weightReps,
                    muscle: "back"
                ),
                PlaceholderExercise(
                    id: "placeholder-overhead-press",
                    canonical: "overhead press (barbell)",
                    display: "Overhead Press (Barbell)",
                    mode: .weightReps,
                    muscle: "shoulders"
                ),
                PlaceholderExercise(
                    id: "placeholder-pull-up",
                    canonical: "pull up",
                    display: "Pull Up",
                    mode: .bodyweightReps,
                    muscle: "back"
                )
            ]
            for item in placeholders {
                try persistence.exercises.upsert(
                    id: item.id,
                    canonicalName: item.canonical,
                    displayName: item.display,
                    exerciseMode: item.mode,
                    isCustom: false,
                    primaryMuscleGroup: item.muscle,
                    isPickerDefault: true
                )
            }
        } catch {
            // Non-fatal; picker may be empty until M5.4 seed lands.
        }
    }
}
