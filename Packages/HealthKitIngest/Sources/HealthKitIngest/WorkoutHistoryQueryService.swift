import CoachLLM
import Core
import Foundation
import Persistence

/// On-demand workout history lookups for coach workout_query.v1.
public struct WorkoutHistoryQueryService: Sendable {
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

    public func run(_ payload: WorkoutQueryPayload, now: Date = Date()) throws -> String {
        let lookback = min(max(payload.lookbackDays ?? 14, 1), 60)
        switch payload.queryType {
        case .latestCompleted:
            return try latestCompleted(lookback: lookback)
        case .onDay:
            return try onDay(payload, now: now)
        case .includingCardio:
            return try includingCardio(lookback: lookback)
        }
    }

    private func latestCompleted(lookback: Int) throws -> String {
        let summaries = try store.workoutSessions.listSummaries(limit: lookback)
        guard let summary = summaries.first else {
            return "query=latestCompleted\nworkouts=none"
        }
        return try formatSession(header: "query=latestCompleted", summary: summary)
    }

    private func onDay(_ payload: WorkoutQueryPayload, now: Date) throws -> String {
        let today = HelmDay.day(for: now, cutoff: cutoff, calendar: calendar)
        guard let day = parseDay(payload.helmDay) ?? Optional(today) else {
            return "error=missing_helmDay"
        }
        let summaries = try store.workoutSessions.listSummaries(limit: 40).filter { summary in
            HelmDay.day(for: summary.startedAt, cutoff: cutoff, calendar: calendar) == day
        }
        guard !summaries.isEmpty else {
            return "query=onDay day=\(day.formatted)\nworkouts=none"
        }
        var blocks: [String] = ["query=onDay day=\(day.formatted) count=\(summaries.count)"]
        for summary in summaries {
            blocks.append(try formatSession(header: "session", summary: summary))
        }
        return blocks.joined(separator: "\n\n---\n\n")
    }

    private func includingCardio(lookback: Int) throws -> String {
        let summaries = try store.workoutSessions.listSummaries(limit: lookback)
        guard !summaries.isEmpty else {
            return "query=includingCardio\nworkouts=none"
        }
        var blocks: [String] = ["query=includingCardio count=\(summaries.count)"]
        for summary in summaries.prefix(5) {
            blocks.append(try formatSession(header: "session", summary: summary))
        }
        return blocks.joined(separator: "\n\n---\n\n")
    }

    private func formatSession(header: String, summary: WorkoutSessionSummary) throws -> String {
        guard let draft = try store.workoutSessions.fetch(id: summary.id) else {
            return "\(header)\nerror=missing_draft"
        }
        let names = try store.exercises.displayNames(for: draft.exercises.map(\.exerciseID))
        let body = WorkoutExportFormatter.formatForCoachContext(draft: draft, displayNames: names)
        let title = summary.title ?? "Workout"
        let sets = summary.totalSetCount
        let volume = Int(summary.totalVolumeKilograms.rounded())
        let duration: String
        if let ended = summary.endedAt {
            duration = "duration_s=\(Int(ended.timeIntervalSince(summary.startedAt)))"
        } else {
            duration = "duration_s=unknown"
        }
        let started = ISO8601DateFormatter().string(from: summary.startedAt)
        return """
        \(header)
        title=\(title) sets=\(sets) volume_kg=\(volume) \(duration) started=\(started)

        \(body)
        """
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
