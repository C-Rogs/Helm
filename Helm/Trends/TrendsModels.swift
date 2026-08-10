import Core
import DesignSystem
import Foundation
import PlanKit
import ReadinessKit

enum TrendsHistoryWindow: Int, CaseIterable, Identifiable, Sendable {
    case days30 = 30
    case days90 = 90
    case all = 0

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .days30: "30d"
        case .days90: "90d"
        case .all: "All"
        }
    }

    /// Inclusive lookback in calendar days; `nil` means unbounded.
    var lookbackDays: Int? {
        switch self {
        case .days30, .days90: rawValue
        case .all: nil
        }
    }
}

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
    let scheduledSets: Double
    let landmarks: VolumeLandmarks
    let state: HelmState
    /// Calendar days since the muscle last received hard-set credit; `nil` when never trained.
    let daysSinceTrained: Int?

    var id: MuscleGroup { muscle }
    var projectedSets: Double { weeklySets + scheduledSets }
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
