import CoachLLM
import Core
import Foundation
import Persistence
import ReadinessKit

/// On-demand trend history lookups for coach trends_query.v1.
struct TrendsHistoryQueryService {
    private let store: PersistenceStore
    private let calendar: Calendar
    private let cutoff: DayCutoff

    init(
        store: PersistenceStore,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) {
        self.store = store
        self.calendar = calendar
        self.cutoff = cutoff
    }

    func run(_ payload: TrendsQueryPayload) throws -> String {
        let lookback = min(max(payload.lookbackDays ?? 30, 1), 90)
        switch payload.queryType {
        case .trimp:
            return try trimpHistory(lookback: lookback)
        case .weight:
            return try weightTrend(lookback: lookback)
        case .e1rm:
            return try e1rmProgression(exerciseName: payload.exerciseName, lookback: lookback)
        case .energyBalance:
            return try energyBalanceHistory(lookback: lookback)
        case .readiness:
            return try readinessHistory(lookback: lookback)
        case .all:
            return try allTrends(lookback: lookback)
        }
    }

    private func trimpHistory(lookback: Int) throws -> String {
        let today = HelmDay.day(for: Date(), cutoff: cutoff, calendar: calendar)
        let startDay = today.adding(days: -(lookback - 1), calendar: calendar)
        let metrics = try store.dailyMetrics.fetchRange(from: startDay, through: today)
        let sorted = metrics.sorted { $0.helmDay < $1.helmDay }
        if sorted.isEmpty {
            return "query=trimp lookback=\(lookback)\ntrimp=none"
        }
        var lines = ["query=trimp lookback=\(lookback)"]
        for metric in sorted {
            if let trimp = metric.priorDayTRIMP {
                lines.append("\(metric.helmDay.formatted) trimp=\(format(trimp))")
            }
        }
        if let stateJSON = try? store.readiness.fetchBaselineJSON(),
           let data = stateJSON.data(using: .utf8),
           let baseline = try? JSONDecoder().decode(ReadinessBaselineState.self, from: data),
           let trimpP75 = baseline.trimpP75 {
            lines.append("trimp_p75_baseline=\(format(trimpP75))")
        }
        return lines.joined(separator: "\n")
    }

    private func weightTrend(lookback: Int) throws -> String {
        let today = HelmDay.day(for: Date(), cutoff: cutoff, calendar: calendar)
        let (bodyWeight, trendWeight, _) = try TrendsDataBuilder.buildTrendWeightPage(
            store: store,
            endingAt: today,
            offset: 0,
            targetWeightKg: nil,
            calendar: calendar
        )
        if bodyWeight.isEmpty {
            return "query=weight lookback=\(lookback)\nweight=none"
        }
        let todayDay = today
        let filtered = trendWeight.filter {
            todayDay.days(to: $0.helmDay, calendar: calendar) <= lookback
        }
        var lines = ["query=weight lookback=\(lookback)"]
        for point in filtered {
            lines.append("\(point.helmDay.formatted) trend_weight=\(format(point.trendWeightKg))kg")
        }
        return lines.joined(separator: "\n")
    }

    private func e1rmProgression(exerciseName: String?, lookback: Int) throws -> String {
        let exerciseLabel = exerciseName ?? "default"
        let exerciseID: String
        if let name = exerciseName, !name.isEmpty {
            let catalog = try store.exercises.fetchCatalogRows()
            let match = catalog.first { $0.displayName.lowercased() == name.lowercased() }
            exerciseID = match?.id ?? TrendsDataBuilder.defaultExerciseID
        } else {
            exerciseID = TrendsDataBuilder.defaultExerciseID
        }
        let (points, _) = try TrendsDataBuilder.buildE1RMPage(
            store: store,
            exerciseID: exerciseID,
            offset: 0,
            calendar: calendar,
            cutoff: cutoff
        )
        let today = HelmDay.day(for: Date(), cutoff: cutoff, calendar: calendar)
        let filtered = points.filter {
            let day = HelmDay.day(for: $0.achievedAt, cutoff: cutoff, calendar: calendar)
            return today.days(to: day, calendar: calendar) <= lookback
        }
        if filtered.isEmpty {
            return "query=e1rm exercise=\(exerciseLabel) lookback=\(lookback)\ne1rm=none"
        }
        var lines = ["query=e1rm exercise=\(exerciseLabel) lookback=\(lookback)"]
        for point in filtered {
            lines.append("\(point.helmDay.formatted) e1rm=\(format(point.e1RMKilograms))kg")
        }
        return lines.joined(separator: "\n")
    }

    private func energyBalanceHistory(lookback: Int) throws -> String {
        let today = HelmDay.day(for: Date(), cutoff: cutoff, calendar: calendar)
        let (gauges, _) = try TrendsDataBuilder.buildEnergyBalancePage(
            store: store,
            endingAt: today,
            offset: 0,
            calendar: calendar
        )
        let filtered = gauges.filter {
            today.days(to: $0.helmDay, calendar: calendar) <= lookback
        }
        if filtered.isEmpty {
            return "query=energyBalance lookback=\(lookback)\nenergy_balance=none"
        }
        var lines = ["query=energyBalance lookback=\(lookback)"]
        for gauge in filtered {
            let delta = gauge.intakeKcal - gauge.targetKcal
            let deltaStr = signed(delta)
            lines.append(
                "\(gauge.helmDay.formatted) intake=\(format(gauge.intakeKcal))kcal target=\(format(gauge.targetKcal))kcal delta=\(deltaStr) state=\(gauge.state.rawValue)"
            )
        }
        return lines.joined(separator: "\n")
    }

    private func readinessHistory(lookback: Int) throws -> String {
        let today = HelmDay.day(for: Date(), cutoff: cutoff, calendar: calendar)
        let (points, _) = try TrendsDataBuilder.buildReadinessPage(
            store: store,
            endingAt: today,
            offset: 0
        )
        let filtered = points.filter {
            today.days(to: $0.helmDay, calendar: calendar) <= lookback
        }
        if filtered.isEmpty {
            return "query=readiness lookback=\(lookback)\nreadiness=none"
        }
        var lines = ["query=readiness lookback=\(lookback)"]
        for point in filtered {
            lines.append("\(point.helmDay.formatted) readiness=\(point.score) state=\(point.state.rawValue)")
        }
        return lines.joined(separator: "\n")
    }

    private func allTrends(lookback: Int) throws -> String {
        let sections = [
            try trimpHistory(lookback: lookback),
            try weightTrend(lookback: lookback),
            try readinessHistory(lookback: lookback),
            try energyBalanceHistory(lookback: lookback)
        ]
        return "query=all lookback=\(lookback)\n\n" + sections.joined(separator: "\n---\n")
    }

    private func format(_ value: Double) -> String {
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private func signed(_ value: Double) -> String {
        value >= 0 ? "+\(format(value))" : "\(format(value))"
    }
}