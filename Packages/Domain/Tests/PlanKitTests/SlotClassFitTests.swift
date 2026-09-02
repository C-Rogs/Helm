import Core
import Foundation
import Testing
@testable import PlanKit

@Suite("Slot class fit")
struct SlotClassFitTests {
    private func chest(
        id: String,
        equipment: String?,
        movementClass: CatalogMovementClass?,
        priority: Int = 0
    ) -> CatalogExercise {
        CatalogExercise(
            exerciseID: id,
            muscleMap: ExerciseMuscleMap(
                exerciseID: id,
                contributions: [ExerciseMuscleContribution(muscle: .chest, fraction: 1)]
            ),
            priority: priority,
            equipment: equipment,
            movementClass: movementClass
        )
    }

    private func biceps(
        id: String,
        equipment: String?,
        movementClass: CatalogMovementClass?,
        priority: Int = 0
    ) -> CatalogExercise {
        CatalogExercise(
            exerciseID: id,
            muscleMap: ExerciseMuscleMap(
                exerciseID: id,
                contributions: [ExerciseMuscleContribution(muscle: .biceps, fraction: 1)]
            ),
            priority: priority,
            equipment: equipment,
            movementClass: movementClass
        )
    }

    @Test("isolation dip loses horizontal press to a loadable push")
    func isolationDipLosesPrimaryPress() {
        let catalog = [
            chest(
                id: "seed-cam-bench-dip",
                equipment: "bodyweight",
                movementClass: .isolation,
                priority: 0
            ),
            chest(
                id: "seed-cam-bench-press",
                equipment: "barbell",
                movementClass: .horizontalPush,
                priority: 1
            )
        ]
        let slot = PatternSlot(
            pattern: .horizontalPress,
            primaryMuscle: .chest,
            role: .primary
        )
        let selection = PlanKit.selectExercise(for: slot, catalog: catalog)
        #expect(selection?.exercise.exerciseID == "seed-cam-bench-press")
    }

    @Test("tagged push beats untagged keyword dip")
    func taggedPushBeatsUntaggedDip() {
        let catalog = [
            chest(
                id: "seed-cam-bench-dip",
                equipment: "bodyweight",
                movementClass: nil,
                priority: 0
            ),
            chest(
                id: "seed-cam-bench-press",
                equipment: "barbell",
                movementClass: .horizontalPush,
                priority: 1
            )
        ]
        let slot = PatternSlot(
            pattern: .horizontalPress,
            primaryMuscle: .chest,
            role: .primary
        )
        let selection = PlanKit.selectExercise(for: slot, catalog: catalog)
        #expect(selection?.exercise.exerciseID == "seed-cam-bench-press")
    }

    @Test("bodyweight push-up loses press slot to barbell when both are horizontalPush")
    func loadabilityPrefersBarbellOnPress() {
        let catalog = [
            chest(
                id: "push_up",
                equipment: "bodyweight",
                movementClass: .horizontalPush
            ),
            chest(
                id: "barbell_bench_press",
                equipment: "barbell",
                movementClass: .horizontalPush
            )
        ]
        let slot = PatternSlot(
            pattern: .horizontalPress,
            primaryMuscle: .chest,
            role: .primary
        )
        let selection = PlanKit.selectExercise(for: slot, catalog: catalog)
        #expect(selection?.exercise.exerciseID == "barbell_bench_press")
    }

    @Test("isolation still fills arms-day curl primary")
    func isolationWinsElbowFlexionPrimary() {
        let catalog = [
            biceps(
                id: "barbell_curl",
                equipment: "barbell",
                movementClass: .isolation
            ),
            CatalogExercise(
                exerciseID: "barbell_row",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "barbell_row",
                    contributions: [
                        ExerciseMuscleContribution(muscle: .back, fraction: 0.7),
                        ExerciseMuscleContribution(muscle: .biceps, fraction: 0.3)
                    ]
                ),
                priority: 0,
                equipment: "barbell",
                movementClass: .horizontalPull
            )
        ]
        let slot = PatternSlot(
            pattern: .elbowFlexion,
            primaryMuscle: .biceps,
            role: .primary
        )
        let selection = PlanKit.selectExercise(for: slot, catalog: catalog)
        #expect(selection?.exercise.exerciseID == "barbell_curl")
    }

    @Test("isolation dip still fills press when it is the only chest option")
    func isolationFallbackWhenNoPushClass() {
        let catalog = [
            chest(
                id: "seed-cam-bench-dip",
                equipment: "bodyweight",
                movementClass: .isolation,
                priority: 0
            )
        ]
        let slot = PatternSlot(
            pattern: .horizontalPress,
            primaryMuscle: .chest,
            role: .primary
        )
        let selection = PlanKit.selectExercise(for: slot, catalog: catalog)
        #expect(selection?.exercise.exerciseID == "seed-cam-bench-dip")
    }

    @Test("missing class still uses keyword matching")
    func unknownClassKeepsKeywordFallback() {
        let catalog = [
            chest(id: "cable_fly", equipment: "cable", movementClass: nil),
            chest(id: "bench_press", equipment: "barbell", movementClass: nil)
        ]
        let slot = PatternSlot(
            pattern: .horizontalPress,
            primaryMuscle: .chest,
            role: .primary
        )
        let selection = PlanKit.selectExercise(for: slot, catalog: catalog)
        #expect(selection?.exercise.exerciseID == "bench_press")
    }

    @Test("parse maps seed strings including other")
    func parseSeedStrings() {
        #expect(CatalogMovementClass.parse("isolation") == .isolation)
        #expect(CatalogMovementClass.parse("horizontalPush") == .horizontalPush)
        #expect(CatalogMovementClass.parse("horizontal_push") == .horizontalPush)
        #expect(CatalogMovementClass.parse("other") == .other)
        #expect(CatalogMovementClass.parse("not-a-class") == .other)
        #expect(CatalogMovementClass.parse(nil) == nil)
        #expect(CatalogMovementClass.parse("") == nil)
    }
}
