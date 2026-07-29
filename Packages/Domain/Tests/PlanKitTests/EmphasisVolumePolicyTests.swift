import Core
import Foundation
import Testing
@testable import PlanKit

@Suite("Emphasis volume policy")
struct EmphasisVolumePolicyTests {
    private func mesocycle(muscles: [MuscleGroup]) -> MesocycleState {
        PlanKit.makeInitialState(muscles: muscles, experience: .intermediate)
    }

    @Test("arm emphasis tracks biceps and triceps for weekly MEV floor")
    func armTrackedMuscles() {
        let muscles = EmphasisVolumePolicy.trackedMuscles(for: "Arms")
        #expect(muscles == [.biceps, .triceps])
    }

    @Test("augmented targets add arm slots without replacing split muscles")
    func augmentedTargets() {
        let base: [MuscleGroup] = [.chest, .shoulders, .triceps]
        let augmented = EmphasisVolumePolicy.augmentedTargetMuscles(base: base, emphasis: "Arms")
        #expect(augmented.contains(.biceps))
        #expect(augmented.contains(.triceps))
        #expect(augmented.contains(.chest))
    }

    @Test("weekly progress sums arm hard sets toward combined MEV floor")
    func weeklyArmProgress() {
        let state = mesocycle(muscles: [.biceps, .triceps])
        let ledger = WeeklyHardSetLedger(
            weekStart: HelmDay(year: 2026, month: 7, day: 28),
            totals: [.biceps: 3, .triceps: 2]
        )

        let progress = EmphasisVolumePolicy.weeklyProgress(
            emphasis: "Arms",
            ledger: ledger,
            mesocycleState: state
        )

        #expect(progress?.label == "Arm emphasis")
        #expect(progress?.doneSets == 5)
        #expect(progress?.targetSets == state.muscles[.biceps]!.landmarks.mev + state.muscles[.triceps]!.landmarks.mev)
        #expect(progress?.displayText == "Arm emphasis · 5/\(progress!.targetSets) sets this week")
    }

    @Test("minimum session sets spread deficit across remaining sessions")
    func minimumSessionSets() {
        let state = mesocycle(muscles: [.biceps, .triceps])
        let ledger = WeeklyHardSetLedger(
            weekStart: HelmDay(year: 2026, month: 7, day: 28),
            totals: [.biceps: 0, .triceps: 0]
        )

        let floor = EmphasisVolumePolicy.minimumSetsThisSession(
            for: .biceps,
            emphasis: "Arms",
            ledger: ledger,
            mesocycleState: state,
            remainingSessionsThisWeek: 3
        )

        let mev = state.muscles[.biceps]!.landmarks.mev
        #expect(floor == Int(ceil(Double(mev) / 3.0)))
    }

    @Test("no minimum sets once MEV floor is met")
    func noFloorWhenMet() {
        let state = mesocycle(muscles: [.biceps, .triceps])
        let mev = state.muscles[.biceps]!.landmarks.mev
        let ledger = WeeklyHardSetLedger(
            weekStart: HelmDay(year: 2026, month: 7, day: 28),
            totals: [.biceps: Double(mev), .triceps: 0]
        )

        let floor = EmphasisVolumePolicy.minimumSetsThisSession(
            for: .biceps,
            emphasis: "Arms",
            ledger: ledger,
            mesocycleState: state,
            remainingSessionsThisWeek: 2
        )

        #expect(floor == nil)
    }

    @Test("empty emphasis leaves targets unchanged")
    func noEmphasis() {
        let base: [MuscleGroup] = [.back, .biceps]
        #expect(EmphasisVolumePolicy.augmentedTargetMuscles(base: base, emphasis: nil) == base)
        #expect(EmphasisVolumePolicy.weeklyProgress(emphasis: nil, ledger: WeeklyHardSetLedger(weekStart: HelmDay(year: 2026, month: 7, day: 28), totals: [:]), mesocycleState: mesocycle(muscles: [.biceps])) == nil)
    }
}

@Suite("Emphasis exercise selection")
struct EmphasisSelectionTests {
    private func armCatalog() -> [CatalogExercise] {
        [
            CatalogExercise(
                exerciseID: "bench_press",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "bench_press",
                    contributions: [
                        ExerciseMuscleContribution(muscle: .chest, fraction: 0.65),
                        ExerciseMuscleContribution(muscle: .triceps, fraction: 0.35)
                    ]
                ),
                priority: 0,
                equipment: "barbell",
                evidence: ExerciseEvidenceRatings(
                    effectiveness: 0.94,
                    stretchPositionBias: 0.72,
                    stimulusToFatigue: 0.82,
                    citationIDs: []
                )
            ),
            CatalogExercise(
                exerciseID: "tricep_pushdown",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "tricep_pushdown",
                    contributions: [ExerciseMuscleContribution(muscle: .triceps, fraction: 1.0)]
                ),
                priority: 1,
                equipment: "cable",
                evidence: ExerciseEvidenceRatings(
                    effectiveness: 0.82,
                    stretchPositionBias: 0.55,
                    stimulusToFatigue: 0.88,
                    citationIDs: []
                )
            ),
            CatalogExercise(
                exerciseID: "barbell_curl",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "barbell_curl",
                    contributions: [ExerciseMuscleContribution(muscle: .biceps, fraction: 1.0)]
                ),
                priority: 0,
                equipment: "barbell",
                evidence: ExerciseEvidenceRatings(
                    effectiveness: 0.80,
                    stretchPositionBias: 0.60,
                    stimulusToFatigue: 0.85,
                    citationIDs: []
                )
            ),
            CatalogExercise(
                exerciseID: "chin_up",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "chin_up",
                    contributions: [
                        ExerciseMuscleContribution(muscle: .back, fraction: 0.55),
                        ExerciseMuscleContribution(muscle: .biceps, fraction: 0.45)
                    ]
                ),
                priority: 1,
                equipment: "bodyweight",
                evidence: ExerciseEvidenceRatings(
                    effectiveness: 0.88,
                    stretchPositionBias: 0.70,
                    stimulusToFatigue: 0.75,
                    citationIDs: []
                )
            )
        ]
    }

    @Test("arm emphasis prefers isolation curls over compounds for biceps")
    func bicepsIsolationBias() {
        let neutral = PlanKit.selectExercise(for: .biceps, catalog: armCatalog())
        let emphasized = PlanKit.selectExercise(
            for: .biceps,
            catalog: armCatalog(),
            emphasisMuscles: [.biceps, .triceps]
        )

        #expect(neutral?.exercise.exerciseID == "barbell_curl")
        #expect(emphasized?.exercise.exerciseID == "barbell_curl")
    }

    @Test("arm emphasis prefers triceps isolation on push slots")
    func tricepsIsolationBias() {
        let neutral = PlanKit.selectExercise(for: .triceps, catalog: armCatalog())
        let emphasized = PlanKit.selectExercise(
            for: .triceps,
            catalog: armCatalog(),
            emphasisMuscles: [.biceps, .triceps]
        )

        #expect(neutral?.exercise.exerciseID == "bench_press")
        #expect(emphasized?.exercise.exerciseID == "tricep_pushdown")
    }
}

@Suite("Emphasis prescription floor")
struct EmphasisPrescriptionTests {
    private let day = HelmDay(year: 2026, month: 7, day: 28)
    private let weekStart = HelmDay(year: 2026, month: 7, day: 27)

    private func armCatalog() -> [CatalogExercise] {
        [
            CatalogExercise(
                exerciseID: "bench_press",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "bench_press",
                    contributions: [
                        ExerciseMuscleContribution(muscle: .chest, fraction: 0.7),
                        ExerciseMuscleContribution(muscle: .triceps, fraction: 0.3)
                    ]
                ),
                priority: 0
            ),
            CatalogExercise(
                exerciseID: "incline_db_press",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "incline_db_press",
                    contributions: [ExerciseMuscleContribution(muscle: .chest, fraction: 1.0)]
                ),
                priority: 1
            ),
            CatalogExercise(
                exerciseID: "lateral_raise",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "lateral_raise",
                    contributions: [ExerciseMuscleContribution(muscle: .shoulders, fraction: 1.0)]
                ),
                priority: 0
            ),
            CatalogExercise(
                exerciseID: "tricep_pushdown",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "tricep_pushdown",
                    contributions: [ExerciseMuscleContribution(muscle: .triceps, fraction: 1.0)]
                ),
                priority: 0
            ),
            CatalogExercise(
                exerciseID: "barbell_curl",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "barbell_curl",
                    contributions: [ExerciseMuscleContribution(muscle: .biceps, fraction: 1.0)]
                ),
                priority: 0
            )
        ]
    }

    @Test("arm emphasis push day still prescribes biceps work toward weekly floor")
    func pushDayIncludesBicepsSets() {
        let muscles: [MuscleGroup] = [.chest, .shoulders, .triceps, .biceps]
        let mesocycle = PlanKit.makeInitialState(muscles: muscles, experience: .intermediate)
        let profile = PrescriptionProfile(
            helmDay: day,
            phaseGoal: PhaseGoal(phase: .maintain, emphasis: "Arms"),
            mesocycleState: mesocycle,
            experience: .intermediate,
            targetMuscles: muscles,
            exerciseCatalog: armCatalog(),
            remainingSessionsThisWeek: 3
        )
        let history = PrescriptionHistory(loggedSets: [], sessions: [], weekStart: weekStart)

        let session = PlanKit.prescription(for: profile, givenReadiness: nil, history: history)
        let biceps = session.exercises.first { $0.exerciseID == "barbell_curl" }

        #expect(biceps != nil)
        #expect((biceps?.targetSets ?? 0) >= 2)
    }
}
