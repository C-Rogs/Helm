import Core
import Foundation
import ReadinessKit
import Testing
@testable import PlanKit

@Suite("Session autoregulator")
struct SessionAutoregulatorTests {
    private let day = HelmDay(year: 2026, month: 8, day: 5)

    private func mesocycle() -> MesocycleState {
        PlanKit.makeInitialState(muscles: [.chest, .back], experience: .intermediate)
    }

    private func depletedGating() -> ReadinessGatingEffect {
        ReadinessGating.effect(
            for: ReadinessScore(
                score: 20,
                band: .depleted,
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
                    rawScore: 20,
                    dampedScore: 20
                ),
                effectiveHRVMilliseconds: 40,
                restingHeartRate: 60
            )
        )
    }

    @Test("depleted gating trims isolation before compounds")
    func trimsIsolationFirst() {
        let session = PrescribedSession(
            helmDay: day,
            exercises: [
                PrescribedExercise(exerciseID: "bench", order: 0, targetSets: 4, targetRPE: 8),
                PrescribedExercise(exerciseID: "fly", order: 1, targetSets: 3, targetRPE: 8)
            ]
        )
        let gating = depletedGating()
        let context = SessionAutoregulationContext(
            exerciseRoles: ["bench": .primary, "fly": .isolation],
            muscleMaps: [
                "bench": ExerciseMuscleMap(
                    exerciseID: "bench",
                    contributions: [ExerciseMuscleContribution(muscle: .chest, fraction: 1)]
                ),
                "fly": ExerciseMuscleMap(
                    exerciseID: "fly",
                    contributions: [ExerciseMuscleContribution(muscle: .chest, fraction: 1)]
                )
            ],
            mesocycleState: mesocycle(),
            weeklyLedger: WeeklyHardSetLedger(weekStart: day, totals: [:]),
            remainingSessionsThisWeek: 2
        )

        let adjusted = SessionAutoregulator.apply(session: session, gating: gating, context: context)
        let fly = adjusted.exercises.first { $0.exerciseID == "fly" }
        let bench = adjusted.exercises.first { $0.exerciseID == "bench" }
        #expect((fly?.targetSets ?? 0) <= 3)
        #expect((bench?.targetSets ?? 0) >= (fly?.targetSets ?? 0))
        #expect(adjusted.exercises.compactMap(\.targetRPE).max() ?? 0 <= gating.rpeCap)
    }

    @Test("depleted gating converts surviving work to technique RPE")
    func techniqueFallback() {
        let session = PrescribedSession(
            helmDay: day,
            exercises: [
                PrescribedExercise(exerciseID: "bench", order: 0, targetSets: 2, targetRPE: 8)
            ]
        )
        let gating = depletedGating()
        let context = SessionAutoregulationContext(
            exerciseRoles: ["bench": .primary],
            muscleMaps: [
                "bench": ExerciseMuscleMap(
                    exerciseID: "bench",
                    contributions: [ExerciseMuscleContribution(muscle: .chest, fraction: 1)]
                )
            ],
            mesocycleState: mesocycle(),
            weeklyLedger: WeeklyHardSetLedger(weekStart: day, totals: [:]),
            remainingSessionsThisWeek: 1
        )

        let adjusted = SessionAutoregulator.apply(session: session, gating: gating, context: context)
        #expect(adjusted.exercises.first?.targetRPE == 6.0)
    }
}

@Suite("Reactive deload policy")
struct ReactiveDeloadPolicyTests {
    @Test("three depleted days proposes pending reactive deload")
    func proposesAfterStreak() {
        var state = PlanKit.makeInitialState(muscles: [.chest], experience: .intermediate)
        for _ in 0..<3 {
            state = PlanKit.recordReadinessForReactiveDeload(state: state, band: .depleted)
        }
        #expect(state.pendingReactiveDeload)
        #expect(state.consecutiveDepletedDays == 3)
    }

    @Test("confirm flips muscles into deload week")
    func confirmAppliesDeloadWeek() {
        var state = PlanKit.makeInitialState(muscles: [.chest], experience: .intermediate)
        state.pendingReactiveDeload = true
        state = PlanKit.confirmReactiveDeload(state)
        #expect(state.pendingReactiveDeload == false)
        #expect(state.muscles[.chest]?.phase == .deload)
    }

    @Test("declining performance proposes reactive deload")
    func decliningPerformanceProposes() {
        let state = PlanKit.makeInitialState(muscles: [.chest], experience: .intermediate)
        let updated = PlanKit.recordReadinessForReactiveDeload(
            state: state,
            band: .balanced,
            toleranceByMuscle: [.chest: ToleranceSignals(performanceTrend: .declining)]
        )
        #expect(updated.pendingReactiveDeload)
    }
}
