import Core
import Foundation
import Testing
@testable import PlanKit

@Suite("Selection bias")
struct SelectionBiasTests {
    private let chestCitations = ["ev-chest-1", "ev-chest-2"]

    private func chestEvidence(
        effectiveness: Double,
        stretch: Double,
        sfr: Double
    ) -> ExerciseEvidenceRatings {
        ExerciseEvidenceRatings(
            effectiveness: effectiveness,
            stretchPositionBias: stretch,
            stimulusToFatigue: sfr,
            citationIDs: chestCitations
        )
    }

    private func chestCatalog() -> [CatalogExercise] {
        [
            CatalogExercise(
                exerciseID: "bench_press",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "bench_press",
                    contributions: [ExerciseMuscleContribution(muscle: .chest, fraction: 1.0)]
                ),
                priority: 0,
                equipment: "barbell",
                evidence: chestEvidence(effectiveness: 0.94, stretch: 0.72, sfr: 0.82)
            ),
            CatalogExercise(
                exerciseID: "incline_db_press",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "incline_db_press",
                    contributions: [ExerciseMuscleContribution(muscle: .chest, fraction: 1.0)]
                ),
                priority: 1,
                equipment: "dumbbell",
                evidence: chestEvidence(effectiveness: 0.86, stretch: 0.88, sfr: 0.76)
            )
        ]
    }

    @Test("stretch bias prefers higher stretch-position movement")
    func stretchBias() {
        let balanced = PlanKit.selectExercise(for: .chest, catalog: chestCatalog())
        let stretch = PlanKit.selectExercise(
            for: .chest,
            catalog: chestCatalog(),
            selectionBias: .stretch
        )

        #expect(balanced?.exercise.exerciseID == "bench_press")
        #expect(stretch?.exercise.exerciseID == "incline_db_press")
    }
}
