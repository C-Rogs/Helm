import Core
import Foundation
import Persistence
import PlanKit

struct TrainingOverviewSnapshot: Sendable, Hashable {
    let sessionCount: Int
    let helmSessionCount: Int
    let totalSets: Int
    let totalVolumeKg: Double
    let totalDurationSeconds: Int
    let priorSessionCount: Int
    let priorTotalSets: Int
    let priorTotalVolumeKg: Double

    var sessionsPerWeek: Double {
        guard windowDays > 0 else { return 0 }
        return Double(sessionCount) / Double(windowDays) * 7.0
    }

    var priorSessionsPerWeek: Double {
        guard windowDays > 0 else { return 0 }
        return Double(priorSessionCount) / Double(windowDays) * 7.0
    }

    let windowDays: Int

    static let empty = TrainingOverviewSnapshot(
        sessionCount: 0,
        helmSessionCount: 0,
        totalSets: 0,
        totalVolumeKg: 0,
        totalDurationSeconds: 0,
        priorSessionCount: 0,
        priorTotalSets: 0,
        priorTotalVolumeKg: 0,
        windowDays: 30
    )
}

struct MuscleDistributionRow: Identifiable, Sendable, Hashable {
    let muscle: MuscleGroup
    let hardSets: Double
    let sessionDays: Int

    var id: MuscleGroup { muscle }
}

struct ExerciseProgressRowModel: Identifiable, Sendable, Hashable {
    let exerciseID: String
    let displayName: String
    let metricKind: ExerciseProgressMetricKind
    let sessionCount: Int
    let latestLabel: String
    let deltaLabel: String?
    let deltaIsPositive: Bool

    var id: String { exerciseID }
}

enum ExerciseProgressMetricKind: Sendable, Hashable {
    case weight
    case bodyweight
    case duration
    case cardio

    var unitLabel: String {
        switch self {
        case .weight: "e1RM"
        case .bodyweight: "best reps"
        case .duration: "best time"
        case .cardio: "best distance"
        }
    }
}

struct ProgressAnalyticsSnapshot: Sendable, Equatable {
    var window: TrendsHistoryWindow
    var overview: TrainingOverviewSnapshot
    var muscleDistribution: [MuscleDistributionRow]
    var exerciseHighlights: [ExerciseProgressRowModel]

    static let empty = ProgressAnalyticsSnapshot(
        window: .days90,
        overview: .empty,
        muscleDistribution: [],
        exerciseHighlights: []
    )
}

enum ProgressAnalyticsMath {
    static func percentChange(current: Double, prior: Double) -> Double? {
        guard prior > 0 else { return nil }
        return ((current - prior) / prior) * 100.0
    }

    static func signedPercentLabel(_ percent: Double?) -> String? {
        guard let percent else { return nil }
        let rounded = Int(percent.rounded())
        if rounded == 0 { return "flat" }
        return rounded > 0 ? "+\(rounded)%" : "\(rounded)%"
    }
}

/// Calendar span for analytics windows, including genuine all-history ranges.
enum ProgressAnalyticsWindowResolver {
    struct Range: Sendable, Equatable {
        let startDay: HelmDay
        let endDay: HelmDay
        let windowDays: Int
        let priorStartDay: HelmDay
        let priorEndDay: HelmDay
    }

    static func resolve(
        window: TrendsHistoryWindow,
        endDay: HelmDay,
        earliestSessionDay: HelmDay?,
        calendar: Calendar = .current
    ) -> Range {
        let startDay: HelmDay
        let windowDays: Int

        if let lookback = window.lookbackDays {
            windowDays = lookback
            startDay = endDay.adding(days: -(lookback - 1), calendar: calendar)
        } else {
            startDay = earliestSessionDay ?? endDay
            windowDays = max(1, startDay.days(to: endDay, calendar: calendar) + 1)
        }

        let priorEndDay = startDay.adding(days: -1, calendar: calendar)
        let priorStartDay = priorEndDay.adding(days: -(windowDays - 1), calendar: calendar)

        return Range(
            startDay: startDay,
            endDay: endDay,
            windowDays: windowDays,
            priorStartDay: priorStartDay,
            priorEndDay: priorEndDay
        )
    }
}
