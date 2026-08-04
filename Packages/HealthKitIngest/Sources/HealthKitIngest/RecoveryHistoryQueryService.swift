import CoachLLM
import Core
import Foundation
import Persistence

/// On-demand recovery / sleep / HRV lookups for coach recovery_query.v1.
public struct RecoveryHistoryQueryService: Sendable {
    private let store: PersistenceStore
    private let calendar: Calendar
    private let cutoff: DayCutoff

    public init(
        store: PersistenceStore,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) {
        self.store = store
        self.calendar = calendar
        self.cutoff = cutoff
    }

    public func run(_ payload: RecoveryQueryPayload, now: Date = Date()) async throws -> String {
        let today = HelmDay.day(for: now, cutoff: cutoff, calendar: calendar)
        switch payload.queryType {
        case .today:
            return try await dayDetail(helmDay: today, query: "today")
        case .day:
            let day = parseDay(payload.helmDay) ?? today
            return try await dayDetail(helmDay: day, query: "day")
        case .range:
            return try await range(lookback: payload.lookbackDays ?? 14, endingAt: today)
        case .sleepDetail:
            let day = parseDay(payload.helmDay) ?? today
            let sleep = try CoachContextAssembler.sleepDetailText(
                from: store,
                helmDay: day,
                calendar: calendar
            )
            return "query=sleepDetail\n\(sleep)"
        }
    }

    private func dayDetail(helmDay: HelmDay, query: String) async throws -> String {
        let context = try await CoachContextAssembler.assemble(
            from: store,
            endingAt: helmDay,
            lookbackDays: 1,
            calendar: calendar,
            cutoff: cutoff
        )
        let dayLine = context.recent.first(where: { $0.helmDay == helmDay })?.text
            ?? context.recent.last?.text
            ?? "no_data"
        let sleep = try CoachContextAssembler.sleepDetailText(
            from: store,
            helmDay: helmDay,
            calendar: calendar
        )
        var blocks = [
            "query=\(query) day=\(helmDay.formatted)",
            dayLine
        ]
        if !context.readinessBaselines.isEmpty {
            blocks.append("baselines:\n\(context.readinessBaselines)")
        }
        blocks.append(sleep)
        return blocks.joined(separator: "\n")
    }

    private func range(lookback: Int, endingAt endDay: HelmDay) async throws -> String {
        let days = min(max(lookback, 1), 60)
        let context = try await CoachContextAssembler.assemble(
            from: store,
            endingAt: endDay,
            lookbackDays: days,
            calendar: calendar,
            cutoff: cutoff
        )
        guard !context.recent.isEmpty else {
            return "query=range lookback=\(days)\ndays=none"
        }
        var lines = ["query=range lookback=\(days) count=\(context.recent.count)"]
        if !context.readinessBaselines.isEmpty {
            lines.append("baselines:\n\(context.readinessBaselines)")
        }
        for day in context.recent.sorted(by: { $0.helmDay < $1.helmDay }) {
            lines.append("\(day.helmDay.formatted) \(day.text)")
        }
        return lines.joined(separator: "\n")
    }

    private func parseDay(_ raw: String?) -> HelmDay? {
        guard let raw else { return nil }
        let parts = raw.split(separator: "-").map(String.init)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        return HelmDay(year: year, month: month, day: day)
    }
}
