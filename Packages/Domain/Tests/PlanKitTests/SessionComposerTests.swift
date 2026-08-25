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
        #expect(session.exercises.allSatisfy { $0.targetSets >= 2 })
        let primaryPullIDs = Set(session.exercises.map(\.exerciseID))
            .intersection(["lat_pulldown", "seated_cable_row"])
        #expect(primaryPullIDs.count >= 2)
        #expect(session.exercises.filter { primaryPullIDs.contains($0.exerciseID) }
            .allSatisfy { $0.targetSets >= 3 })
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

    @Test("upper 60-minute table is not push-like")
    func upperSixtyMinuteNotPushLike() {
        let upper = SessionComposer.slots(
            dayKind: .upper,
            budget: .minutes60,
            template: .upperLower,
            readinessBand: .balanced,
            isDeload: false
        )
        let push = SessionComposer.slots(
            dayKind: .push,
            budget: .minutes60,
            template: .ppl,
            readinessBand: .balanced,
            isDeload: false
        )
        let upperPatterns = Set(upper.map(\.pattern))
        #expect(upper.count >= 4)
        #expect(upperPatterns.contains(.horizontalPress))
        #expect(upperPatterns.contains(.verticalPull))
        #expect(upperPatterns.contains(.horizontalPull))
        #expect(upperPatterns.contains(.verticalPress))
        #expect(!Set(push.map(\.pattern)).contains(.verticalPull))
        #expect(upper.map(\.pattern) != push.map(\.pattern))
    }

    @Test("upper 45-minute table keeps press and pull")
    func upperFortyFivePressAndPull() {
        let slots = SessionComposer.slots(
            dayKind: .upper,
            budget: .minutes45,
            template: .upperLower
        )
        let patterns = Set(slots.map(\.pattern))
        #expect(slots.count >= 3)
        #expect(patterns.contains(.horizontalPress))
        #expect(patterns.contains(.verticalPull))
    }

    @Test("lower 60-minute table keeps squat and hinge")
    func lowerSixtyMinuteSquatHinge() {
        let slots = SessionComposer.slots(
            dayKind: .lower,
            budget: .minutes60,
            template: .upperLower
        )
        let patterns = Set(slots.map(\.pattern))
        #expect(slots.count >= 4)
        #expect(patterns.contains(.kneeExtensionCompound))
        #expect(patterns.contains(.hipHinge))
        #expect(patterns.contains(.unilateralKnee))
        #expect(patterns.contains(.kneeFlexion))
    }

    @Test("full-body 60-minute table covers lower, press, and pull")
    func fullBodySixtyMinuteVectors() {
        let slots = SessionComposer.slots(
            dayKind: .full,
            budget: .minutes60,
            template: .fullBody
        )
        let patterns = Set(slots.map(\.pattern))
        #expect(slots.count >= 4)
        #expect(patterns.contains(.kneeExtensionCompound))
        #expect(patterns.contains(.horizontalPress))
        #expect(patterns.contains(.verticalPull) || patterns.contains(.horizontalPull))
        #expect(patterns.contains(.hipHinge))
    }

    @Test("30-minute and deload allow the two-exercise exception")
    func twoExerciseDefectExceptions() {
        #expect(
            SessionComposer.allowsThinSession(
                budget: .minutes30,
                readinessBand: .balanced,
                isDeload: false
            )
        )
        #expect(
            SessionComposer.allowsThinSession(
                budget: .minutes60,
                readinessBand: .balanced,
                isDeload: true
            )
        )
        let thirty = SessionComposer.slots(dayKind: .upper, budget: .minutes30)
        #expect(thirty.count == 2)
        #expect(thirty.map(\.pattern) == [.horizontalPress, .verticalPull])
    }

    @Test("UL and FB templates expose dedicated tables")
    func dedicatedSlotTableFlags() {
        for template in ProgramTemplate.allCases {
            #expect(template.hasDedicatedSlotTables)
        }
        #expect(!ProgramTemplate.upperLower.detail.localizedCaseInsensitiveContains("coming next"))
        #expect(!ProgramTemplate.fullBody.detail.localizedCaseInsensitiveContains("coming next"))
        #expect(ProgramTemplate.upperLower.label == "Upper / Lower")
        #expect(ProgramTemplate.fullBody.label == "Full Body")
    }

    @Test("composed upper prescription fills press and pull when catalog covers patterns")
    func upperPrescriptionDensity() {
        let day = HelmDay(year: 2026, month: 8, day: 5)
        let weekStart = HelmDay(year: 2026, month: 8, day: 3)
        let catalog = [
            CatalogExercise(
                exerciseID: "bench_press",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "bench_press",
                    contributions: [ExerciseMuscleContribution(muscle: .chest, fraction: 1)]
                ),
                priority: 0
            ),
            CatalogExercise(
                exerciseID: "lat_pulldown",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "lat_pulldown",
                    contributions: [ExerciseMuscleContribution(muscle: .back, fraction: 1)]
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
                exerciseID: "seated_row",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "seated_row",
                    contributions: [ExerciseMuscleContribution(muscle: .back, fraction: 1)]
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
                exerciseID: "dumbbell_curl",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "dumbbell_curl",
                    contributions: [ExerciseMuscleContribution(muscle: .biceps, fraction: 1)]
                ),
                priority: 1
            ),
            CatalogExercise(
                exerciseID: "triceps_pushdown",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "triceps_pushdown",
                    contributions: [ExerciseMuscleContribution(muscle: .triceps, fraction: 1)]
                ),
                priority: 1
            )
        ]
        let muscles: [MuscleGroup] = [.chest, .back, .shoulders, .biceps, .triceps]
        let profile = PrescriptionProfile(
            helmDay: day,
            phaseGoal: PhaseGoal(phase: .maintain),
            mesocycleState: PlanKit.makeInitialState(muscles: muscles, experience: .intermediate),
            experience: .intermediate,
            targetMuscles: muscles,
            exerciseCatalog: catalog,
            remainingSessionsThisWeek: 2,
            durationBudget: .minutes60,
            programTemplate: .upperLower,
            dayKind: .upper
        )
        let session = PlanKit.prescription(
            for: profile,
            givenReadiness: nil,
            history: PrescriptionHistory(loggedSets: [], sessions: [], weekStart: weekStart)
        )
        #expect(session.exercises.count >= 4)
        #expect(session.exercises.allSatisfy { $0.targetSets >= 2 })
        #expect(session.exercises.allSatisfy { $0.targetSets <= 4 })
        let ids = Set(session.exercises.map(\.exerciseID))
        #expect(ids.contains("bench_press"))
        #expect(ids.contains("lat_pulldown"))
    }
}
