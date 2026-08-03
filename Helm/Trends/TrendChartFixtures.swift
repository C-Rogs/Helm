import Core
import DesignSystem
import Foundation
import PlanKit

enum TrendChartFixtures {
    static let today = HelmDay(year: 2026, month: 7, day: 23)

    static var bodyWeight: [TrendWeightPoint] {
        let noise: [Double] = [0.3, -0.2, 0.5, -0.4, 0.1, -0.3, 0.2, -0.1, 0.4, -0.5, 0.15, -0.25, 0.35, -0.15]
        return (0 ..< 14).map { offset in
            let day = today.adding(days: -(13 - offset))
            let weight = 78.4 + Double(offset) * 0.08 + noise[offset]
            return TrendWeightPoint(
                helmDay: day,
                trendWeightKg: weight,
                state: HelmState.readiness(score: 55 + Double(offset) * 2)
            )
        }
    }

    static var trendWeight: [TrendWeightPoint] {
        (0 ..< 14).map { offset in
            let day = today.adding(days: -(13 - offset))
            let weight = 78.4 + Double(offset) * 0.08
            return TrendWeightPoint(
                helmDay: day,
                trendWeightKg: weight,
                state: HelmState.readiness(score: 55 + Double(offset) * 2)
            )
        }
    }

    static let targetWeightKg = 80.0

    static var readinessHistory: [ReadinessHistoryPoint] {
        [42, 48, 55, 61, 58, 72, 68, 74, 63, 59, 66, 71, 77, 62].enumerated().map { index, score in
            ReadinessHistoryPoint(
                helmDay: today.adding(days: -(13 - index)),
                score: score,
                state: HelmState.readiness(score: Double(score))
            )
        }
    }

    static var muscleVolume: [MuscleVolumeGauge] {
        muscleVolumeStates
    }

    static var muscleVolumeStates: [MuscleVolumeGauge] {
        [
            MuscleVolumeGauge(
                muscle: .quads,
                weeklySets: 4,
                scheduledSets: 6,
                landmarks: VolumeLandmarks(mev: 8, mrv: 18),
                state: .ready,
                daysSinceTrained: 5
            ),
            MuscleVolumeGauge(
                muscle: .chest,
                weeklySets: 14,
                scheduledSets: 0,
                landmarks: VolumeLandmarks(mev: 10, mrv: 20),
                state: .ready,
                daysSinceTrained: 2
            ),
            MuscleVolumeGauge(
                muscle: .back,
                weeklySets: 18,
                scheduledSets: 3,
                landmarks: VolumeLandmarks(mev: 10, mrv: 18),
                state: .compromised,
                daysSinceTrained: 0
            ),
            MuscleVolumeGauge(
                muscle: .hamstrings,
                weeklySets: 22,
                scheduledSets: 0,
                landmarks: VolumeLandmarks(mev: 8, mrv: 16),
                state: .compromised,
                daysSinceTrained: 1
            ),
        ]
    }

    static var e1RMHistory: [E1RMProgressionPoint] {
        [118, 120, 119, 122, 124, 123, 126, 127, 125, 128].enumerated().map { index, value in
            E1RMProgressionPoint(
                helmDay: today.adding(days: -(9 - index) * 3),
                achievedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 86_400 * 3),
                e1RMKilograms: Double(value)
            )
        }
    }

    static var energyBalance: [EnergyBalanceGauge] {
        [2_420, 2_680, 2_510, 2_740, 2_600, 2_790, 2_550].enumerated().map { index, intake in
            let target = 2_650.0
            return EnergyBalanceGauge(
                helmDay: today.adding(days: -(6 - index)),
                intakeKcal: Double(intake),
                targetKcal: target,
                state: HelmState.energyBalance(intakeKcal: Double(intake), targetKcal: target)
            )
        }
    }

    static var snapshot: TrendsSnapshot {
        TrendsSnapshot(
            bodyWeight: bodyWeight,
            trendWeight: trendWeight,
            targetWeightKg: targetWeightKg,
            readinessHistory: readinessHistory,
            muscleVolume: muscleVolume,
            e1RMHistory: e1RMHistory,
            selectedExerciseID: "exercise-squat",
            selectedExerciseName: "Squat (Barbell)",
            energyBalance: energyBalance,
            canLoadMoreHistory: false
        )
    }
}
