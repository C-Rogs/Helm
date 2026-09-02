import Core
import Foundation
import ReadinessKit
import Testing
@testable import PlanKit

@Suite("Standing constraint prescription")
struct StandingConstraintPrescriptionTests {
    private let day = HelmDay(year: 2026, month: 8, day: 5)
    private let weekStart = HelmDay(year: 2026, month: 8, day: 3)

    @Test("policy maps joints to patterns")
    func policyMapping() {
        #expect(
            StandingConstraintPatternPolicy.excludedPatterns(forActiveJoints: ["shoulder"])
                == [.verticalPress]
        )
        #expect(
            StandingConstraintPatternPolicy.excludedPatterns(forActiveJoints: ["knee"])
                == [.kneeExtensionCompound, .unilateralKnee]
        )
        #expect(
            StandingConstraintPatternPolicy.excludedPatterns(forActiveJoints: ["wrist"]).isEmpty
        )
        #expect(
            StandingConstraintPatternPolicy.excludedPatterns(forActiveJoints: ["shoulder", "knee"])
                == [.verticalPress, .kneeExtensionCompound, .unilateralKnee]
        )
    }

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
                exerciseID: "seed-cam-bench-dip",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "seed-cam-bench-dip",
                    contributions: [ExerciseMuscleContribution(muscle: .chest, fraction: 1)]
                ),
                priority: 0,
                equipment: "bodyweight",
                movementClass: .isolation
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

    private func legCatalog() -> [CatalogExercise] {
        [
            CatalogExercise(
                exerciseID: "back_squat",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "back_squat",
                    contributions: [ExerciseMuscleContribution(muscle: .quads, fraction: 1)]
                ),
                priority: 0
            ),
            CatalogExercise(
                exerciseID: "bulgarian_split_squat",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "bulgarian_split_squat",
                    contributions: [ExerciseMuscleContribution(muscle: .quads, fraction: 1)]
                ),
                priority: 0
            ),
            CatalogExercise(
                exerciseID: "leg_curl",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "leg_curl",
                    contributions: [ExerciseMuscleContribution(muscle: .hamstrings, fraction: 1)]
                ),
                priority: 0
            ),
            CatalogExercise(
                exerciseID: "romanian_deadlift",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "romanian_deadlift",
                    contributions: [ExerciseMuscleContribution(muscle: .hamstrings, fraction: 1)]
                ),
                priority: 0
            ),
            CatalogExercise(
                exerciseID: "standing_calf_raise",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "standing_calf_raise",
                    contributions: [ExerciseMuscleContribution(muscle: .calves, fraction: 1)]
                ),
                priority: 0
            )
        ]
    }

    private func mesocycle(muscles: [MuscleGroup]) -> MesocycleState {
        PlanKit.makeInitialState(muscles: muscles, experience: .intermediate)
    }

    @Test("active shoulder excludedPatterns skips overhead press")
    func excludesOHP() {
        let excluded = StandingConstraintPatternPolicy.excludedPatterns(forActiveJoints: ["shoulder"])
        let profile = PrescriptionProfile(
            helmDay: day,
            phaseGoal: PhaseGoal(phase: .maintain),
            mesocycleState: mesocycle(muscles: [.chest, .shoulders, .triceps]),
            experience: .intermediate,
            targetMuscles: [.chest, .shoulders, .triceps],
            exerciseCatalog: pushCatalog(),
            remainingSessionsThisWeek: 2,
            durationBudget: .minutes60,
            dayKind: .push,
            excludedPatterns: excluded
        )
        let session = PlanKit.prescription(
            for: profile,
            givenReadiness: nil,
            history: PrescriptionHistory(loggedSets: [], sessions: [], weekStart: weekStart)
        )
        let ids = Set(session.exercises.map(\.exerciseID))
        #expect(!ids.contains("overhead_press"))
        #expect(!ids.contains("seed-cam-bench-dip"))
        #expect(ids.contains("bench_press") || ids.contains("cable_fly"))
    }

    @Test("active knee excludedPatterns skips squat and lunge patterns")
    func excludesKneePatterns() {
        let excluded = StandingConstraintPatternPolicy.excludedPatterns(forActiveJoints: ["knee"])
        let profile = PrescriptionProfile(
            helmDay: day,
            phaseGoal: PhaseGoal(phase: .maintain),
            mesocycleState: mesocycle(muscles: [.quads, .hamstrings, .calves]),
            experience: .intermediate,
            targetMuscles: [.quads, .hamstrings, .calves],
            exerciseCatalog: legCatalog(),
            remainingSessionsThisWeek: 2,
            durationBudget: .minutes60,
            dayKind: .legs,
            excludedPatterns: excluded
        )
        let session = PlanKit.prescription(
            for: profile,
            givenReadiness: nil,
            history: PrescriptionHistory(loggedSets: [], sessions: [], weekStart: weekStart)
        )
        let ids = Set(session.exercises.map(\.exerciseID))
        #expect(!ids.contains("back_squat"))
        #expect(!ids.contains("bulgarian_split_squat"))
        #expect(ids.contains("leg_curl") || ids.contains("romanian_deadlift") || ids.contains("standing_calf_raise"))
    }

    @Test("without excludedPatterns overhead press can be selected")
    func allowsOHPWithoutExclusion() {
        let profile = PrescriptionProfile(
            helmDay: day,
            phaseGoal: PhaseGoal(phase: .maintain),
            mesocycleState: mesocycle(muscles: [.chest, .shoulders, .triceps]),
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
