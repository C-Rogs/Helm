import Core
import Foundation
import ReadinessKit
import Testing
@testable import PlanKit

@Suite("Prescription engine")
struct PrescriptionEngineTests {
    private let day = HelmDay(year: 2026, month: 7, day: 23)
    private let weekStart = HelmDay(year: 2026, month: 7, day: 21)

    private func catalog() -> [CatalogExercise] {
        [
            CatalogExercise(
                exerciseID: "bench_press",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "bench_press",
                    contributions: [ExerciseMuscleContribution(muscle: .chest, fraction: 1.0)]
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
                exerciseID: "squat",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "squat",
                    contributions: [ExerciseMuscleContribution(muscle: .quads, fraction: 1.0)]
                ),
                priority: 0
            ),
            CatalogExercise(
                exerciseID: "leg_press",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "leg_press",
                    contributions: [ExerciseMuscleContribution(muscle: .quads, fraction: 1.0)]
                ),
                priority: 1
            )
        ]
    }

    private func mesocycle() -> MesocycleState {
        PlanKit.makeInitialState(
            muscles: [.chest, .quads],
            experience: .intermediate
        )
    }

    private func profile(phase: TrainingPhase = .maintain) -> PrescriptionProfile {
        PrescriptionProfile(
            helmDay: day,
            phaseGoal: PhaseGoal(phase: phase),
            mesocycleState: mesocycle(),
            experience: .intermediate,
            targetMuscles: [.chest, .quads],
            exerciseCatalog: catalog(),
            remainingSessionsThisWeek: 2
        )
    }

    private func readiness(score: Int, band: ReadinessBand) -> ReadinessScore {
        ReadinessScore(
            score: score,
            band: band,
            confidence: .high,
            confidenceValue: 0.9,
            hrvBand: .typical,
            validNights: 14,
            stabilityScore: 0.8,
            contributors: ReadinessContributorBreakdown(
                zHRV: 0,
                zRestingHR: 0,
                zSleep: 0,
                zRespiratory: nil,
                zTemperature: nil,
                zStrain: 0,
                zComposite: 0,
                rawScore: Double(score),
                dampedScore: Double(score)
            ),
            effectiveHRVMilliseconds: 50,
            restingHeartRate: 55
        )
    }

    private func totalSets(in session: PrescribedSession) -> Int {
        session.exercises.reduce(0) { $0 + $1.targetSets }
    }

    private func maxRPE(in session: PrescribedSession) -> Double {
        session.exercises.compactMap(\.targetRPE).max() ?? 0
    }

    @Test("low-readiness prescriptions are strictly lighter than primed")
    func lowReadinessIsLighter() {
        let history = PrescriptionHistory(loggedSets: [], sessions: [], weekStart: weekStart)
        let depleted = readiness(score: 20, band: .depleted)
        let primed = readiness(score: 80, band: .primed)

        let lightSession = PlanKit.prescription(
            for: profile(),
            givenReadiness: depleted,
            history: history
        )
        let heavySession = PlanKit.prescription(
            for: profile(),
            givenReadiness: primed,
            history: history
        )

        #expect(totalSets(in: lightSession) < totalSets(in: heavySession))
        #expect(maxRPE(in: lightSession) < maxRPE(in: heavySession))
    }

    @Test("changing phase re-plans volume")
    func phaseChangeReplans() {
        let history = PrescriptionHistory(loggedSets: [], sessions: [], weekStart: weekStart)
        let cutSession = PlanKit.prescription(
            for: profile(phase: .cut),
            givenReadiness: nil,
            history: history
        )
        let gainSession = PlanKit.prescription(
            for: profile(phase: .gain),
            givenReadiness: nil,
            history: history
        )

        #expect(totalSets(in: cutSession) < totalSets(in: gainSession))
    }

    @Test("prescription carries progression targets from history")
    func progressionTargets() {
        let historySets = [
            LoggedSet(
                exerciseID: "bench_press",
                sequence: 1,
                mass: Mass(kilograms: 80),
                reps: 10,
                rir: 2,
                completedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        ]
        let history = PrescriptionHistory(
            loggedSets: historySets,
            sessions: [],
            weekStart: weekStart
        )
        let session = PlanKit.prescription(
            for: profile(),
            givenReadiness: nil,
            history: history
        )
        let bench = session.exercises.first { $0.exerciseID == "bench_press" }
        #expect(bench?.targetMass?.kilograms == 80)
        #expect(bench?.targetRepMin == 8)
        #expect(bench?.targetRepMax == 12)
    }
}

@Suite("Prescription adjustments")
struct PrescriptionAdjustmentTests {
    private let day = HelmDay(year: 2026, month: 7, day: 23)

    private var catalog: [CatalogExercise] {
        [
            CatalogExercise(
                exerciseID: "bench_press",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "bench_press",
                    contributions: [ExerciseMuscleContribution(muscle: .chest, fraction: 1.0)]
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
                exerciseID: "cable_fly",
                muscleMap: ExerciseMuscleMap(
                    exerciseID: "cable_fly",
                    contributions: [ExerciseMuscleContribution(muscle: .chest, fraction: 1.0)]
                ),
                priority: 2
            )
        ]
    }

    private var session: PrescribedSession {
        PrescribedSession(
            helmDay: day,
            exercises: [
                PrescribedExercise(
                    exerciseID: "bench_press",
                    order: 0,
                    targetSets: 3,
                    targetRepMin: 8,
                    targetRepMax: 12,
                    targetMass: Mass(kilograms: 80),
                    targetRPE: 8
                )
            ]
        )
    }

    @Test("set removals floor at one rather than rejecting")
    func setRemovalFloorsAtOne() {
        let result = PlanKit.apply(
            adjustment: PrescriptionAdjustment(operations: [
                PrescriptionAdjustmentOperation(
                    kind: .adjustSets,
                    exerciseID: "bench_press",
                    setDelta: -3
                )
            ]),
            to: session,
            excluding: [],
            catalog: catalog
        )

        guard case .applied(let adjusted) = result else {
            Issue.record("Expected set removal to apply")
            return
        }
        #expect(adjusted.exercises.first?.targetSets == 1)
    }

    @Test("set adds past the engine cap apply")
    func setAddPastEngineCapApplies() {
        let result = PlanKit.apply(
            adjustment: PrescriptionAdjustment(operations: [
                PrescriptionAdjustmentOperation(
                    kind: .adjustSets,
                    exerciseID: "bench_press",
                    setDelta: 10
                )
            ]),
            to: session,
            excluding: [],
            catalog: catalog
        )

        guard case .applied(let adjusted) = result else {
            Issue.record("Expected set add to apply")
            return
        }
        #expect(adjusted.exercises.first?.targetSets == 13)
    }


    @Test("exclude list honoured across repeated swaps")
    func excludeListHonouredAcrossSwaps() {
        var excluded: Set<String> = []
        var current = session

        let first = PlanKit.apply(
            adjustment: PrescriptionAdjustment(operations: [
                PrescriptionAdjustmentOperation(kind: .swap, fromExerciseID: "bench_press")
            ]),
            to: current,
            excluding: excluded,
            catalog: catalog
        )
        guard case .applied(let swappedOnce) = first else {
            Issue.record("Expected first swap to apply")
            return
        }
        #expect(swappedOnce.exercises[0].exerciseID == "incline_db_press")
        excluded.insert("bench_press")
        excluded.insert("incline_db_press")
        current = swappedOnce

        let second = PlanKit.apply(
            adjustment: PrescriptionAdjustment(operations: [
                PrescriptionAdjustmentOperation(
                    kind: .swap,
                    fromExerciseID: "incline_db_press",
                    excludeExerciseIDs: Array(excluded)
                )
            ]),
            to: current,
            excluding: excluded,
            catalog: catalog
        )
        guard case .applied(let swappedTwice) = second else {
            Issue.record("Expected second swap to apply")
            return
        }
        #expect(swappedTwice.exercises[0].exerciseID == "cable_fly")
        #expect(!excluded.contains(swappedTwice.exercises[0].exerciseID))
    }

    @Test("swap rejects explicitly excluded target")
    func rejectsExcludedSwapTarget() {
        let result = PlanKit.apply(
            adjustment: PrescriptionAdjustment(operations: [
                PrescriptionAdjustmentOperation(
                    kind: .swap,
                    fromExerciseID: "bench_press",
                    toExerciseID: "incline_db_press"
                )
            ]),
            to: session,
            excluding: ["incline_db_press"],
            catalog: catalog
        )

        guard case .rejected(.swapTargetExcluded(let exerciseID)) = result else {
            Issue.record("Expected swapTargetExcluded rejection")
            return
        }
        #expect(exerciseID == "incline_db_press")
    }

    @Test("load adjustment applies within bounds")
    func adjustLoadApplies() {
        let result = PlanKit.apply(
            adjustment: PrescriptionAdjustment(operations: [
                PrescriptionAdjustmentOperation(
                    kind: .adjustLoad,
                    exerciseID: "bench_press",
                    massDeltaKg: 2.5
                )
            ]),
            to: session,
            excluding: [],
            catalog: catalog
        )

        guard case .applied(let adjusted) = result else {
            Issue.record("Expected load adjustment to apply")
            return
        }
        #expect(adjusted.exercises[0].targetMass?.kilograms == 82.5)
    }

    @Test("large coach-suggested load increase applies")
    func largeCoachLoadIncreaseApplies() {
        let result = PlanKit.apply(
            adjustment: PrescriptionAdjustment(operations: [
                PrescriptionAdjustmentOperation(
                    kind: .adjustLoad,
                    exerciseID: "bench_press",
                    massDeltaKg: 20
                )
            ]),
            to: session,
            excluding: [],
            catalog: catalog
        )

        guard case .applied(let adjusted) = result else {
            Issue.record("Expected load increase to apply")
            return
        }
        #expect(adjusted.exercises[0].targetMass?.kilograms == 100)
    }

    @Test("user-directed load decrease applies")
    func userDirectedDecreaseApplies() {
        let result = PlanKit.apply(
            adjustment: PrescriptionAdjustment(operations: [
                PrescriptionAdjustmentOperation(
                    kind: .adjustLoad,
                    exerciseID: "bench_press",
                    massDeltaKg: -15,
                    loadAdjustmentIntent: .userDirected
                )
            ]),
            to: session,
            excluding: [],
            catalog: catalog
        )

        guard case .applied(let adjusted) = result else {
            Issue.record("Expected user-directed load decrease to apply")
            return
        }
        #expect(adjusted.exercises[0].targetMass?.kilograms == 65)
    }

    @Test("coach-suggested load decrease is not capped above floor")
    func coachSuggestedDecreaseApplies() {
        let result = PlanKit.apply(
            adjustment: PrescriptionAdjustment(operations: [
                PrescriptionAdjustmentOperation(
                    kind: .adjustLoad,
                    exerciseID: "bench_press",
                    massDeltaKg: -15,
                    loadAdjustmentIntent: .coachSuggested
                )
            ]),
            to: session,
            excluding: [],
            catalog: catalog
        )

        guard case .applied(let adjusted) = result else {
            Issue.record("Expected coach-suggested load decrease to apply")
            return
        }
        #expect(adjusted.exercises[0].targetMass?.kilograms == 65)
    }

    @Test("load adjustment clamps to zero floor")
    func loadClampsToZero() {
        let result = PlanKit.apply(
            adjustment: PrescriptionAdjustment(operations: [
                PrescriptionAdjustmentOperation(
                    kind: .adjustLoad,
                    exerciseID: "bench_press",
                    massDeltaKg: -100,
                    loadAdjustmentIntent: .userDirected
                )
            ]),
            to: session,
            excluding: [],
            catalog: catalog
        )

        guard case .applied(let adjusted) = result else {
            Issue.record("Expected load to clamp to zero")
            return
        }
        #expect(adjusted.exercises[0].targetMass?.kilograms == 0)
    }

    @Test("RPE adjustment applies within bounds")
    func adjustRPEApplies() {
        let result = PlanKit.apply(
            adjustment: PrescriptionAdjustment(operations: [
                PrescriptionAdjustmentOperation(
                    kind: .adjustRPE,
                    exerciseID: "bench_press",
                    rpeDelta: 0.5
                )
            ]),
            to: session,
            excluding: [],
            catalog: catalog
        )

        guard case .applied(let adjusted) = result else {
            Issue.record("Expected RPE adjustment to apply")
            return
        }
        #expect(adjusted.exercises[0].targetRPE == 8.5)
    }
}
