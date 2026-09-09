import Core
import Foundation
import Persistence
import PlanKit

enum ProgressAnalyticsBuilder {
    static func build(
        store: PersistenceStore,
        window: TrendsHistoryWindow,
        endingAt endDay: HelmDay,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) throws -> ProgressAnalyticsSnapshot {
        let earliestSessionDay = try store.workoutSessions.earliestCompletedSessionDay(
            calendar: calendar,
            cutoff: cutoff
        )
        let range = ProgressAnalyticsWindowResolver.resolve(
            window: window,
            endDay: endDay,
            earliestSessionDay: earliestSessionDay,
            calendar: calendar
        )

        let current = try store.workoutSessions.fetchTrainingOverviewAggregate(
            since: range.startDay,
            through: range.endDay,
            calendar: calendar,
            cutoff: cutoff
        )
        let prior = try store.workoutSessions.fetchTrainingOverviewAggregate(
            since: range.priorStartDay,
            through: range.priorEndDay,
            calendar: calendar,
            cutoff: cutoff
        )

        let overview = TrainingOverviewSnapshot(
            sessionCount: current.sessionCount,
            helmSessionCount: current.helmSessionCount,
            totalSets: current.totalSets,
            totalVolumeKg: current.totalVolumeKg,
            totalDurationSeconds: current.totalDurationSeconds,
            priorSessionCount: prior.sessionCount,
            priorTotalSets: prior.totalSets,
            priorTotalVolumeKg: prior.totalVolumeKg,
            windowDays: range.windowDays
        )

        let muscleDistribution = try buildMuscleDistribution(
            store: store,
            startDay: range.startDay,
            endDay: range.endDay,
            windowDays: range.windowDays,
            calendar: calendar,
            cutoff: cutoff
        )

        let highlights = try store.workoutSessions.fetchExerciseProgressHighlights(
            since: range.startDay,
            through: range.endDay,
            priorSince: range.priorStartDay,
            priorThrough: range.priorEndDay,
            calendar: calendar,
            cutoff: cutoff
        )
        let exerciseHighlights = highlights.map(mapExerciseHighlight)

        return ProgressAnalyticsSnapshot(
            window: window,
            overview: overview,
            muscleDistribution: muscleDistribution,
            exerciseHighlights: exerciseHighlights
        )
    }

    private static func buildMuscleDistribution(
        store: PersistenceStore,
        startDay: HelmDay,
        endDay: HelmDay,
        windowDays: Int,
        calendar: Calendar,
        cutoff: DayCutoff
    ) throws -> [MuscleDistributionRow] {
        let sessions = try TrendsDataBuilder.loadSessionsForSummary(
            store: store,
            since: startDay,
            calendar: calendar,
            cutoff: cutoff
        )
        let muscleMaps = try TrendsDataBuilder.muscleMaps(from: store)
        let ledger = PlanKit.rollingHardSetTotals(
            sessions: sessions,
            muscleMaps: muscleMaps,
            endingAt: endDay,
            windowDays: windowDays
        )

        let sessionDays = sessionDaysByMuscle(
            sessions: sessions,
            muscleMaps: muscleMaps,
            startDay: startDay,
            endDay: endDay,
            calendar: calendar,
            cutoff: cutoff
        )

        return MuscleGroup.allCases.compactMap { muscle in
            let sets = ledger.totals[muscle, default: 0]
            let days = sessionDays[muscle, default: 0]
            guard sets > 0 || days > 0 else { return nil }
            return MuscleDistributionRow(
                muscle: muscle,
                hardSets: sets,
                sessionDays: days
            )
        }
        .sorted { $0.hardSets > $1.hardSets }
    }

    private static func sessionDaysByMuscle(
        sessions: [WorkoutSession],
        muscleMaps: [String: ExerciseMuscleMap],
        startDay: HelmDay,
        endDay: HelmDay,
        calendar: Calendar,
        cutoff: DayCutoff
    ) -> [MuscleGroup: Int] {
        var daysByMuscle: [MuscleGroup: Set<HelmDay>] = [:]

        for session in sessions where session.helmDay >= startDay && session.helmDay <= endDay {
            var musclesInSession = Set<MuscleGroup>()
            for set in session.sets {
                guard let map = muscleMaps[set.exerciseID] else { continue }
                for contribution in map.contributions {
                    musclesInSession.insert(contribution.muscle)
                }
            }
            for muscle in musclesInSession {
                daysByMuscle[muscle, default: []].insert(session.helmDay)
            }
        }

        return Dictionary(uniqueKeysWithValues: daysByMuscle.map { ($0.key, $0.value.count) })
    }

    private static func mapExerciseHighlight(
        _ highlight: WorkoutSessionRepository.ExerciseProgressHighlight
    ) -> ExerciseProgressRowModel {
        let metricKind = metricKind(for: highlight.exerciseMode)
        let latestLabel = formattedValue(
            highlight.latestValue,
            metricKind: metricKind
        )
        let deltaLabel: String?
        let deltaIsPositive: Bool
        if let prior = highlight.priorValue {
            let delta = highlight.latestValue - prior
            deltaLabel = formattedDelta(delta, metricKind: metricKind)
            deltaIsPositive = delta >= 0
        } else {
            deltaLabel = nil
            deltaIsPositive = true
        }

        return ExerciseProgressRowModel(
            exerciseID: highlight.exerciseID,
            displayName: highlight.displayName,
            metricKind: metricKind,
            sessionCount: highlight.sessionCount,
            latestLabel: latestLabel,
            deltaLabel: deltaLabel,
            deltaIsPositive: deltaIsPositive
        )
    }

    private static func metricKind(for mode: ExerciseMode) -> ExerciseProgressMetricKind {
        switch mode {
        case .weightReps: .weight
        case .bodyweightReps: .bodyweight
        case .duration: .duration
        case .distanceDuration: .cardio
        }
    }

    private static func formattedValue(_ value: Double, metricKind: ExerciseProgressMetricKind) -> String {
        switch metricKind {
        case .weight:
            return String(format: "%.0f kg", value)
        case .bodyweight:
            return String(format: "%.0f reps", value.rounded())
        case .duration:
            let minutes = Int(value.rounded()) / 60
            let seconds = Int(value.rounded()) % 60
            return String(format: "%d:%02d", minutes, seconds)
        case .cardio:
            return String(format: "%.1f km", value)
        }
    }

    private static func formattedDelta(_ delta: Double, metricKind: ExerciseProgressMetricKind) -> String {
        switch metricKind {
        case .weight:
            let rounded = delta.rounded()
            return rounded == 0 ? "flat" : String(format: "%+.0f kg", rounded)
        case .bodyweight:
            let rounded = delta.rounded()
            return rounded == 0 ? "flat" : String(format: "%+.0f reps", rounded)
        case .duration:
            let seconds = Int(delta.rounded())
            if seconds == 0 { return "flat" }
            let sign = seconds > 0 ? "+" : "-"
            let absolute = abs(seconds)
            return String(format: "%@%d:%02d", sign, absolute / 60, absolute % 60)
        case .cardio:
            let rounded = delta
            if abs(rounded) < 0.05 { return "flat" }
            return String(format: "%+.1f km", rounded)
        }
    }
}
