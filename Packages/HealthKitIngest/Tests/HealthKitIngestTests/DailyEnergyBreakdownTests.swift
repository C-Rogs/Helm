import Core
import Foundation
import Testing
@testable import HealthKitIngest

@Suite("Daily energy breakdown")
struct DailyEnergyBreakdownTests {
    private let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let endedAt = Date(timeIntervalSince1970: 1_700_001_800)

    @Test("total out equals resting plus active and workouts stay nested")
    func totalOutIsRestingPlusActive() {
        let breakdown = DailyEnergyBreakdownBuilder.build(
            intakeKcal: 2_200,
            restingKcal: 1_650,
            activeKcal: 520,
            activeFreshness: .fresh(kilocalories: 520),
            workouts: [
                workout(
                    id: "run",
                    source: .healthKit,
                    title: "Run",
                    activityType: "Running",
                    energy: 320
                ),
                workout(
                    id: "push",
                    source: .manual,
                    title: "Push",
                    energy: 180
                ),
            ],
            bodyMassKilograms: 80
        )

        #expect(breakdown.restingKcal == 1_650)
        #expect(breakdown.activeKcal == 520)
        #expect(breakdown.totalOutKcal == 2_170)
        #expect(breakdown.netKcal == 30)
        #expect(breakdown.workoutContributors.count == 2)
        #expect(breakdown.workoutContributors.map(\.kilocalories).reduce(0, +) == 500)
        #expect(breakdown.otherActivity == .reconciled(kilocalories: 20))
    }

    @Test("reconciled other activity is active minus workout contributors")
    func reconciledOtherActivity() {
        let breakdown = DailyEnergyBreakdownBuilder.build(
            intakeKcal: 1_900,
            restingKcal: 1_600,
            activeKcal: 600,
            activeFreshness: .fresh(kilocalories: 600),
            workouts: [
                workout(
                    id: "run",
                    source: .healthKit,
                    title: "CrossFit",
                    activityType: "Cross Training",
                    energy: 420
                ),
            ],
            bodyMassKilograms: 75
        )

        #expect(breakdown.otherActivity == .reconciled(kilocalories: 180))
        #expect(breakdown.workoutContributors.first?.provenance == .healthKitWorkout)
        #expect(breakdown.workoutContributors.first?.detail == "Apple Fitness · Cross Training")
    }

    @Test("stale active energy shows syncing instead of negative other activity")
    func staleActiveShowsSyncing() {
        let other = DailyEnergyBreakdownBuilder.resolveOtherActivity(
            activeKcal: nil,
            activeFreshness: .stale(partialKilocalories: nil),
            workoutTotalKcal: 250
        )

        #expect(other == .syncing)

        let breakdown = DailyEnergyBreakdownBuilder.build(
            intakeKcal: 1_800,
            restingKcal: 1_650,
            activeKcal: nil,
            activeFreshness: .stale(partialKilocalories: nil),
            workouts: [
                workout(
                    id: "run",
                    source: .healthKit,
                    title: "Run",
                    activityType: "Running",
                    energy: 250
                ),
            ],
            bodyMassKilograms: 75
        )

        #expect(breakdown.otherActivity == .syncing)
        #expect(breakdown.totalOutKcal == nil)
        #expect(breakdown.netKcal == nil)
    }

    @Test("total out and net require both resting and active")
    func partialComponentsOmitTotalOutAndNet() {
        let restingOnly = DailyEnergyBreakdownBuilder.build(
            intakeKcal: 1_800,
            restingKcal: 1_650,
            activeKcal: nil,
            activeFreshness: .unavailable,
            workouts: [],
            bodyMassKilograms: 75
        )
        #expect(restingOnly.restingKcal == 1_650)
        #expect(restingOnly.totalOutKcal == nil)
        #expect(restingOnly.netKcal == nil)

        let activeOnly = DailyEnergyBreakdownBuilder.build(
            intakeKcal: 1_800,
            restingKcal: nil,
            activeKcal: 420,
            activeFreshness: .fresh(kilocalories: 420),
            workouts: [],
            bodyMassKilograms: 75
        )
        #expect(activeOnly.activeKcal == 420)
        #expect(activeOnly.totalOutKcal == nil)
        #expect(activeOnly.netKcal == nil)
    }

    @Test("helm workout without hk energy uses estimator")
    func estimatedHelmWorkoutContributor() {
        let breakdown = DailyEnergyBreakdownBuilder.build(
            intakeKcal: 2_000,
            restingKcal: 1_650,
            activeKcal: 450,
            activeFreshness: .fresh(kilocalories: 450),
            workouts: [
                DailyEnergyBreakdownBuilder.WorkoutEnergyWorkoutInput(
                    id: "session-1",
                    title: "Legs",
                    source: .manual,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    activityType: nil,
                    activeEnergyKilocalories: nil
                ),
            ],
            bodyMassKilograms: 80
        )

        #expect(breakdown.workoutContributors.count == 1)
        #expect(breakdown.workoutContributors.first?.provenance == .estimated)
        #expect(breakdown.workoutContributors.first?.kilocalories == 240)
    }

    @Test("workout sum above active shows unreconciled state")
    func unreconciledWhenWorkoutsExceedActive() {
        let other = DailyEnergyBreakdownBuilder.resolveOtherActivity(
            activeKcal: 300,
            activeFreshness: .fresh(kilocalories: 300),
            workoutTotalKcal: 420
        )

        #expect(other == .unreconciled(workoutTotalKcal: 420, activeTotalKcal: 300))
    }

    private func workout(
        id: String,
        source: WorkoutSessionSource,
        title: String,
        activityType: String? = nil,
        energy: Double
    ) -> DailyEnergyBreakdownBuilder.WorkoutEnergyWorkoutInput {
        DailyEnergyBreakdownBuilder.WorkoutEnergyWorkoutInput(
            id: id,
            title: title,
            source: source,
            startedAt: startedAt,
            endedAt: endedAt,
            activityType: activityType,
            activeEnergyKilocalories: energy
        )
    }
}
