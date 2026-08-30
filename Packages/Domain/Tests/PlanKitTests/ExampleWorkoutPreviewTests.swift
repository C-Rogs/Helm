import Core
import Foundation
import Testing
@testable import PlanKit

@Suite("Example workout preview")
struct ExampleWorkoutPreviewTests {
    @Test("pull catalog fills a pull example without empty rows")
    func pullExampleNonEmpty() {
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
            )
        ]
        let lines = PlanKit.exampleWorkout(
            dayKind: .pull,
            budget: .minutes60,
            template: .ppl,
            catalog: catalog
        )
        #expect(!lines.isEmpty)
        #expect(Set(lines.map(\.exerciseID)).count == lines.count)
        #expect(lines.allSatisfy { $0.targetSets >= 2 })
    }
}
