import Core
import Foundation
import ReadinessKit
import Testing
@testable import PlanKit

@Suite("Evidence-driven exercise selection")
struct ExerciseSelectionTests {
    private let day = HelmDay(year: 2026, month: 7, day: 23)
    private let weekStart = HelmDay(year: 2026, month: 7, day: 21)

    private let chestCitations = ["ev-chest-1", "ev-chest-2"]

    private func chestEvidence(
        effectiveness: Double,
        stretch: Double,
        sfr: Double,
        citations: [String] = ["ev-chest-1"]
    ) -> ExerciseEvidenceRatings {
        ExerciseEvidenceRatings(
            effectiveness: effectiveness,
            stretchPositionBias: stretch,
            stimulusToFatigue: sfr,
            citationIDs: citations
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
                evidence: chestEvidence(effectiveness: 0.94, stretch: 0.72, sfr: 0.82, citations: chestCitations)
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
            ),
            CatalogExercise(
                exerciseID: "cable_fly",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "cable_fly",
                    contributions: [ExerciseMuscleContribution(muscle: .chest, fraction: 1.0)]
                ),
                priority: 2,
                equipment: "cable",
                evidence: chestEvidence(effectiveness: 0.75, stretch: 0.90, sfr: 0.85)
            ),
            CatalogExercise(
                exerciseID: "machine_press",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "machine_press",
                    contributions: [ExerciseMuscleContribution(muscle: .chest, fraction: 1.0)]
                ),
                priority: 3,
                equipment: "machine",
                evidence: chestEvidence(effectiveness: 0.70, stretch: 0.40, sfr: 0.92)
            )
        ]
    }

    private func quadCatalog() -> [CatalogExercise] {
        [
            CatalogExercise(
                exerciseID: "squat",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "squat",
                    contributions: [ExerciseMuscleContribution(muscle: .quads, fraction: 1.0)]
                ),
                priority: 0,
                equipment: "barbell",
                evidence: ExerciseEvidenceRatings(
                    effectiveness: 0.95,
                    stretchPositionBias: 0.80,
                    stimulusToFatigue: 0.55,
                    citationIDs: ["ev-quad-1"]
                )
            ),
            CatalogExercise(
                exerciseID: "leg_press",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "leg_press",
                    contributions: [ExerciseMuscleContribution(muscle: .quads, fraction: 1.0)]
                ),
                priority: 1,
                equipment: "machine",
                evidence: ExerciseEvidenceRatings(
                    effectiveness: 0.78,
                    stretchPositionBias: 0.45,
                    stimulusToFatigue: 0.88,
                    citationIDs: ["ev-quad-2"]
                )
            )
        ]
    }

    private func mesocycle() -> MesocycleState {
        PlanKit.makeInitialState(muscles: [.chest, .quads], experience: .intermediate)
    }

    private func profile(
        catalog: [CatalogExercise],
        availableEquipment: Set<String>? = nil,
        remainingSessionsThisWeek: Int = 2
    ) -> PrescriptionProfile {
        PrescriptionProfile(
            helmDay: day,
            phaseGoal: PhaseGoal(phase: .maintain),
            mesocycleState: mesocycle(),
            experience: .intermediate,
            targetMuscles: [.chest, .quads],
            exerciseCatalog: catalog,
            remainingSessionsThisWeek: remainingSessionsThisWeek,
            availableEquipment: availableEquipment
        )
    }

    @Test("highest evidence-rated movement wins when equipment is unconstrained")
    func evidenceRanking() {
        let selection = PlanKit.selectExercise(for: .chest, catalog: chestCatalog())
        #expect(selection?.exercise.exerciseID == "bench_press")
        #expect(selection?.evidenceIDs == chestCitations)
        #expect(selection?.rationale.contains("chest") == true)
    }

    @Test("equipment constraints exclude unavailable movements")
    func equipmentConstraints() {
        let selection = PlanKit.selectExercise(
            for: .chest,
            catalog: chestCatalog(),
            availableEquipment: ["dumbbell"]
        )
        #expect(selection?.exercise.exerciseID == "incline_db_press")
        #expect(selection?.exercise.equipment == "dumbbell")
    }

    @Test("excluded movements are never selected")
    func excludedMovements() {
        let selection = PlanKit.selectExercise(
            for: .chest,
            catalog: chestCatalog(),
            excluding: ["bench_press", "incline_db_press"]
        )
        #expect(selection?.exercise.exerciseID == "cable_fly")
    }

    @Test("prescription carries rationale and citation references for every exercise")
    func prescriptionRationaleAndCitations() {
        let catalog = chestCatalog() + quadCatalog()
        let history = PrescriptionHistory(loggedSets: [], sessions: [], weekStart: weekStart)
        let session = PlanKit.prescription(
            for: profile(catalog: catalog),
            givenReadiness: nil,
            history: history
        )

        #expect(session.exercises.count >= 2)
        for exercise in session.exercises {
            #expect(exercise.rationale != nil)
            #expect(!(exercise.rationale ?? "").isEmpty)
            #expect(!exercise.evidenceIDs.isEmpty)
        }
    }

    @Test("weekly muscle targets are satisfied under equipment constraints")
    func weeklyTargetsUnderConstraints() {
        let catalog = chestCatalog() + quadCatalog()
        let priorChestSets = (0 ..< 6).map { index in
            LoggedSet(
                exerciseID: "incline_db_press",
                sequence: index + 1,
                mass: Mass(kilograms: 30),
                reps: 10,
                rir: 2,
                completedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index))
            )
        }
        let priorSession = WorkoutSession(
            helmDay: HelmDay(year: 2026, month: 7, day: 22),
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sets: priorChestSets
        )
        let history = PrescriptionHistory(
            loggedSets: priorChestSets,
            sessions: [priorSession],
            weekStart: weekStart
        )

        let session = PlanKit.prescription(
            for: profile(catalog: catalog, availableEquipment: ["dumbbell", "machine"], remainingSessionsThisWeek: 1),
            givenReadiness: nil,
            history: history
        )

        let chestExercise = session.exercises.first { $0.exerciseID == "incline_db_press" }
        #expect(chestExercise != nil)
        #expect(chestExercise?.targetSets ?? 0 >= 1)

        let muscleMaps = Dictionary(uniqueKeysWithValues: catalog.map { ($0.exerciseID, $0.muscleMap) })
        let ledger = PlanKit.weeklyHardSetTotals(
            sessions: history.sessions,
            muscleMaps: muscleMaps,
            weekStart: weekStart
        )
        let chestTarget = PlanKit.weeklyHardSetTarget(for: mesocycle().muscles[.chest]!)
        let priorChest = ledger.totals[MuscleGroup.chest, default: 0]
        let projectedChest = priorChest + Double(chestExercise?.targetSets ?? 0)
        #expect(projectedChest >= Double(chestTarget) * 0.5)
    }

    @Test("swap refresh attaches rationale for replacement movement")
    func swapRefreshesRationale() {
        let catalog = chestCatalog()
        let session = PrescribedSession(
            helmDay: day,
            exercises: [
                PrescribedExercise(
                    exerciseID: "bench_press",
                    order: 0,
                    targetSets: 3,
                    targetRPE: 8,
                    rationale: "old",
                    evidenceIDs: ["old"]
                )
            ]
        )

        let result = PlanKit.apply(
            adjustment: PrescriptionAdjustment(operations: [
                PrescriptionAdjustmentOperation(kind: .swap, fromExerciseID: "bench_press")
            ]),
            to: session,
            excluding: [],
            catalog: catalog,
            availableEquipment: ["dumbbell"]
        )

        guard case .applied(let updated) = result else {
            Issue.record("Expected swap to apply")
            return
        }
        #expect(updated.exercises[0].exerciseID == "incline_db_press")
        #expect(updated.exercises[0].rationale?.contains("incline") == false)
        #expect(updated.exercises[0].rationale?.contains("chest") == true)
        #expect(!updated.exercises[0].evidenceIDs.isEmpty)
    }

    @Test("picker staples beat obscure stretches without evidence")
    func staplesBeatObscureStretches() {
        let catalog: [CatalogExercise] = [
            CatalogExercise(
                exerciseID: "lying_leg_curl",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "lying_leg_curl",
                    contributions: [ExerciseMuscleContribution(muscle: .hamstrings, fraction: 1.0)]
                ),
                priority: 0,
                equipment: "machine"
            ),
            CatalogExercise(
                exerciseID: "hamstring_stretch",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "hamstring_stretch",
                    contributions: [ExerciseMuscleContribution(muscle: .hamstrings, fraction: 1.0)]
                ),
                priority: 1,
                equipment: "bodyweight"
            )
        ]

        let selection = PlanKit.selectExercise(for: .hamstrings, catalog: catalog)
        #expect(selection?.exercise.exerciseID == "lying_leg_curl")
    }

    @Test("familiar exercises outrank obscure alternatives")
    func familiarExerciseBoost() {
        let catalog: [CatalogExercise] = [
            CatalogExercise(
                exerciseID: "seated_leg_curl",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "seated_leg_curl",
                    contributions: [ExerciseMuscleContribution(muscle: .hamstrings, fraction: 1.0)]
                ),
                priority: 1,
                equipment: "machine"
            ),
            CatalogExercise(
                exerciseID: "hamstring_stretch",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "hamstring_stretch",
                    contributions: [ExerciseMuscleContribution(muscle: .hamstrings, fraction: 1.0)]
                ),
                priority: 1,
                equipment: "bodyweight"
            )
        ]

        let selection = PlanKit.selectExercise(
            for: .hamstrings,
            catalog: catalog,
            familiarExerciseIDs: ["seated_leg_curl"]
        )
        #expect(selection?.exercise.exerciseID == "seated_leg_curl")
    }
}
