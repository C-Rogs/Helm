import Core
import Foundation
import ReadinessKit
import Testing
@testable import PlanKit

@Suite("Session composer")
struct SessionComposerTests {
    @Test("60-minute pull requires at least four pattern slots")
    func pullSixtyMinuteSlots() {
        let slots = SessionComposer.slots(
            dayKind: .pull,
            budget: .minutes60,
            readinessBand: .balanced,
            isDeload: false
        )
        #expect(slots.count >= 4)
        let patterns = Set(slots.map(\.pattern))
        #expect(patterns.contains(.verticalPull))
        #expect(patterns.contains(.horizontalPull))
        #expect(patterns.contains(.elbowFlexion))
    }

    @Test("45-minute pull keeps density floor of three slots")
    func pullFortyFive() {
        let slots = SessionComposer.slots(dayKind: .pull, budget: .minutes45)
        #expect(slots.count >= 3)
        #expect(SessionDurationBudget.minutes45.minimumExerciseFloor == 3)
    }

    @Test("depleted readiness allows thin session exception")
    func depletedAllowsThin() {
        #expect(
            SessionComposer.allowsThinSession(
                budget: .minutes60,
                readinessBand: .depleted,
                isDeload: false
            )
        )
        #expect(
            !SessionComposer.allowsThinSession(
                budget: .minutes60,
                readinessBand: .balanced,
                isDeload: false
            )
        )
    }

    @Test("composed pull prescription fills multiple exercises when catalog covers patterns")
    func pullPrescriptionDensity() {
        let day = HelmDay(year: 2026, month: 8, day: 5)
        let weekStart = HelmDay(year: 2026, month: 8, day: 3)
        let catalog = [
            CatalogExercise(
                exerciseID: "lat_pulldown",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "lat_pulldown",
                    contributions: [ExerciseMuscleContribution(muscle: .back, fraction: 1)]
                ),
                priority: 0
            ),
            CatalogExercise(
                exerciseID: "seated_cable_row",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "seated_cable_row",
                    contributions: [ExerciseMuscleContribution(muscle: .back, fraction: 1)]
                ),
                priority: 0
            ),
            CatalogExercise(
                exerciseID: "dumbbell_curl",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "dumbbell_curl",
                    contributions: [ExerciseMuscleContribution(muscle: .biceps, fraction: 1)]
                ),
                priority: 0
            ),
            CatalogExercise(
                exerciseID: "rear_delt_fly",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "rear_delt_fly",
                    contributions: [ExerciseMuscleContribution(muscle: .shoulders, fraction: 1)]
                ),
                priority: 0
            ),
            CatalogExercise(
                exerciseID: "straight_arm_pulldown",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "straight_arm_pulldown",
                    contributions: [ExerciseMuscleContribution(muscle: .back, fraction: 1)]
                ),
                priority: 1
            )
        ]
        let muscles: [MuscleGroup] = [.back, .biceps, .shoulders]
        let profile = PrescriptionProfile(
            helmDay: day,
            phaseGoal: PhaseGoal(phase: .maintain),
            mesocycleState: PlanKit.makeInitialState(muscles: muscles, experience: .intermediate),
            experience: .intermediate,
            targetMuscles: muscles,
            exerciseCatalog: catalog,
            remainingSessionsThisWeek: 2,
            durationBudget: .minutes60,
            programTemplate: .ppl,
            dayKind: .pull
        )
        let session = PlanKit.prescription(
            for: profile,
            givenReadiness: nil,
            history: PrescriptionHistory(loggedSets: [], sessions: [], weekStart: weekStart)
        )
        #expect(session.exercises.count >= 4)
        #expect(session.exercises.allSatisfy { $0.targetSets <= 4 })
        let ids = Set(session.exercises.map(\.exerciseID))
        #expect(ids.contains("lat_pulldown") || ids.contains("straight_arm_pulldown"))
        #expect(ids.contains("seated_cable_row"))
        #expect(ids.contains("dumbbell_curl"))
    }

    @Test("pattern matcher prefers row for horizontal pull over pulldown")
    func patternMatcherHorizontal() {
        #expect(MovementPatternMatcher.patternScore(exerciseID: "seated_row", pattern: .horizontalPull) > 0)
        #expect(MovementPatternMatcher.patternScore(exerciseID: "lat_pulldown", pattern: .verticalPull) > 0)
        #expect(MovementPatternMatcher.patternScore(exerciseID: "lat_pulldown", pattern: .horizontalPull) == 0)
    }
}
