import Core
import DesignSystem
import Foundation
import PlanKit
import ReadinessKit

struct TrendWeightPoint: Identifiable, Sendable, Hashable {
    let helmDay: HelmDay
    let trendWeightKg: Double
    let state: HelmState

    var id: HelmDay { helmDay }
}

struct ReadinessHistoryPoint: Identifiable, Sendable, Hashable {
    let helmDay: HelmDay
    let score: Int
    let state: HelmState

    var id: HelmDay { helmDay }
}

struct MuscleVolumeGauge: Identifiable, Sendable, Hashable {
    let muscle: MuscleGroup
    let weeklySets: Double
    let landmarks: VolumeLandmarks
    let state: HelmState
    /// Calendar days since the muscle last received hard-set credit; `nil` when never trained.
    let daysSinceTrained: Int?

    var id: MuscleGroup { muscle }
}

struct E1RMProgressionPoint: Identifiable, Sendable, Hashable {
    let helmDay: HelmDay
    let achievedAt: Date
    let e1RMKilograms: Double

    var id: Date { achievedAt }
}

struct EnergyBalanceGauge: Identifiable, Sendable, Hashable {
    let helmDay: HelmDay
    let intakeKcal: Double
    let targetKcal: Double
    let state: HelmState

    var id: HelmDay { helmDay }
}

struct TrendsSnapshot: Sendable, Equatable {
    /// Daily scale readings (unsmoothed).
    var bodyWeight: [TrendWeightPoint]
    /// EWMA-smoothed trend used for TDEE and dashboard at-a-glance.
    var trendWeight: [TrendWeightPoint]
    var targetWeightKg: Double?
    var readinessHistory: [ReadinessHistoryPoint]
    var muscleVolume: [MuscleVolumeGauge]
    var e1RMHistory: [E1RMProgressionPoint]
    var selectedExerciseID: String
    var selectedExerciseName: String
    var energyBalance: [EnergyBalanceGauge]
    var canLoadMoreHistory: Bool

    var hasDisplayedHistory: Bool {
        !trendWeight.isEmpty
            || !readinessHistory.isEmpty
            || !e1RMHistory.isEmpty
            || !energyBalance.isEmpty
    }

    static let empty = TrendsSnapshot(
        bodyWeight: [],
        trendWeight: [],
        targetWeightKg: nil,
        readinessHistory: [],
        muscleVolume: [],
        e1RMHistory: [],
        selectedExerciseID: "",
        selectedExerciseName: "",
        energyBalance: [],
        canLoadMoreHistory: false
    )
}
