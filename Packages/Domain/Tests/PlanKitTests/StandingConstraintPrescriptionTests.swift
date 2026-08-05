import Core
import Foundation
import ReadinessKit
import Testing
@testable import PlanKit

@Suite("Standing constraint prescription")
struct StandingConstraintPrescriptionTests {
    private let day = HelmDay(year: 2026, month: 8, day: 5)
    private let weekStart = HelmDay(year: 2026, month: 8, day: 3)

    private func pushCatalog() -> [CatalogExercise] {
        [
            CatalogExercise(
                exerciseID: "bench_press",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "bench_press",
                    contributions: [ExerciseMuscleContribution(muscle: .chest, fraction: 1)]
                ),
                priority: 0
            ),
            CatalogExercise(
                exerciseID: "overhead_press",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "overhead_press",
                    contributions: [ExerciseMuscleContribution(muscle: .shoulders, fraction: 1)]
                ),
                priority: 0
            ),
            CatalogExercise(
                exerciseID: "dumbbell_lateral_raise",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "dumbbell_lateral_raise",
                    contributions: [ExerciseMuscleContribution(muscle: .shoulders, fraction: 1)]
                ),
                priority: 0
            ),
            CatalogExercise(
                exerciseID: "cable_fly",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "cable_fly",
                    contributions: [ExerciseMuscleContribution(muscle: .chest, fraction: 1)]
                ),
                priority: 0
            ),
            CatalogExercise(
                exerciseID: "triceps_pushdown",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "triceps_pushdown",
                    contributions: [ExerciseMuscleContribution(muscle: .triceps, fraction: 1)]
                ),
                priority: 0
            )
        ]
    }

    private func mesocycle() -> MesocycleState {
        PlanKit.makeInitialState(
            muscles: [.chest, .shoulders, .triceps],
            experience: .intermediate
        )
    }

    @Test("active shoulder excludedPatterns skips overhead press")
    func excludesOHP() {
        let profile = PrescriptionProfile(
            helmDay: day,
            phaseGoal: PhaseGoal(phase: .maintain),
            mesocycleState: mesocycle(),
            experience: .intermediate,
            targetMuscles: [.chest, .shoulders, .triceps],
            exerciseCatalog: pushCatalog(),
            remainingSessionsThisWeek: 2,
            durationBudget: .minutes60,
            dayKind: .push,
            excludedPatterns: [.verticalPress]
        )
        let session = PlanKit.prescription(
            for: profile,
            givenReadiness: nil,
            history: PrescriptionHistory(loggedSets: [], sessions: [], weekStart: weekStart)
        )
        let ids = Set(session.exercises.map(\.exerciseID))
        #expect(!ids.contains("overhead_press"))
        #expect(ids.contains("bench_press") || ids.contains("cable_fly"))
    }

    @Test("without excludedPatterns overhead press can be selected")
    func allowsOHPWithoutExclusion() {
        let profile = PrescriptionProfile(
            helmDay: day,
            phaseGoal: PhaseGoal(phase: .maintain),
            mesocycleState: mesocycle(),
            experience: .intermediate,
            targetMuscles: [.chest, .shoulders, .triceps],
            exerciseCatalog: pushCatalog(),
            remainingSessionsThisWeek: 2,
            durationBudget: .minutes60,
            dayKind: .push,
            excludedPatterns: []
        )
        let session = PlanKit.prescription(
            for: profile,
            givenReadiness: nil,
            history: PrescriptionHistory(loggedSets: [], sessions: [], weekStart: weekStart)
        )
        let ids = Set(session.exercises.map(\.exerciseID))
        #expect(ids.contains("overhead_press"))
    }
}
