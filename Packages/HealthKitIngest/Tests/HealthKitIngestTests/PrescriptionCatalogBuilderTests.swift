import Core
import Persistence
import PlanKit
import Testing
@testable import HealthKitIngest

@Suite("Prescription catalog builder")
struct PrescriptionCatalogBuilderTests {
    @Test("builder forwards seed class and evidence into PlanKit catalog")
    func forwardsClassAndEvidence() {
        let rows = [
            ExerciseCatalogRow(
                id: "seed-cam-bench-dip",
                displayName: "Bench Dip",
                primaryMuscleGroup: "chest",
                secondaryMuscleGroups: [],
                equipment: "bodyweight",
                isPickerDefault: true,
                movementPattern: "isolation"
            ),
            ExerciseCatalogRow(
                id: "seed-cam-bench-press",
                displayName: "Bench Press",
                primaryMuscleGroup: "chest",
                secondaryMuscleGroups: [],
                equipment: "barbell",
                isPickerDefault: true,
                movementPattern: "horizontalPush",
                evidence: ExerciseSeedEvidence(
                    effectivenessRating: 0.9,
                    stretchPositionBias: 0.7,
                    stimulusToFatigue: 0.8,
                    citationIDs: ["ev-chest"]
                )
            )
        ]
        let catalog = PrescriptionCatalogBuilder.build(from: rows)
        let dip = catalog.first { $0.exerciseID == "seed-cam-bench-dip" }
        let bench = catalog.first { $0.exerciseID == "seed-cam-bench-press" }
        #expect(dip?.movementClass == .isolation)
        #expect(dip?.equipment == "bodyweight")
        #expect(bench?.movementClass == .horizontalPush)
        #expect(bench?.evidence?.effectiveness == 0.9)
        #expect(bench?.evidence?.citationIDs == ["ev-chest"])
    }
}
