import Core
import Foundation
import Persistence
import PlanKit

enum PrescriptionHistoryBuilder {
    static func history(
        from store: PersistenceStore,
        endingAt endDay: HelmDay,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) throws -> PrescriptionHistory {
        let weekStart = Self.weekStart(containing: endDay, calendar: calendar)
        let lookbackStart = weekStart.adding(days: -21, calendar: calendar)
        let drafts = try store.workoutSessions.fetchCompletedSessionsForPrescription(
            since: lookbackStart,
            calendar: calendar,
            cutoff: cutoff
        )

        var loggedSets: [LoggedSet] = []
        var sessions: [WorkoutSession] = []

        for draft in drafts {
            let helmDay = HelmDay.day(for: draft.startedAt, cutoff: cutoff, calendar: calendar)
            var sessionSets: [LoggedSet] = []
            var sequence = 0

            for exercise in draft.exercises {
                for set in exercise.sets where set.status == .completed {
                    sequence += 1
                    let logged = LoggedSet(
                        exerciseID: exercise.exerciseID,
                        sequence: sequence,
                        mass: set.mass,
                        reps: set.reps,
                        rir: set.rir.map { Int($0.rounded()) },
                        rpe: set.rpe,
                        completedAt: set.completedAt ?? draft.startedAt,
                        isWarmup: set.setType.isWarmup
                    )
                    loggedSets.append(logged)
                    sessionSets.append(logged)
                }
            }

            sessions.append(
                WorkoutSession(
                    id: UUID(uuidString: draft.id) ?? UUID(),
                    helmDay: helmDay,
                    startedAt: draft.startedAt,
                    finishedAt: draft.endedAt,
                    sets: sessionSets
                )
            )
        }

        return PrescriptionHistory(
            loggedSets: loggedSets,
            sessions: sessions,
            weekStart: weekStart
        )
    }

    static func completedSessionsThisWeek(
        in history: PrescriptionHistory,
        through endDay: HelmDay
    ) -> Int {
        let weekDays = (0 ..< 7).map { history.weekStart.adding(days: $0) }
        let weekDaySet = Set(weekDays)
        return history.sessions.filter { weekDaySet.contains($0.helmDay) && $0.helmDay <= endDay }.count
    }

    static func weekStart(containing day: HelmDay, calendar: Calendar) -> HelmDay {
        var iso = calendar
        iso.firstWeekday = 2
        let components = day.dateComponents()
        guard
            let date = iso.date(from: components),
            let interval = iso.dateInterval(of: .weekOfYear, for: date)
        else {
            return day
        }
        return HelmDay.day(for: interval.start, cutoff: .default, calendar: iso)
    }
}
