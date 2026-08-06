import Core
import Foundation
import Persistence
import PlanKit

public enum PrescriptionHistoryBuilder {
    public static func history(
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
                        setType: set.setType
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

    public static func completedSessionsThisWeek(
        in history: PrescriptionHistory,
        through endDay: HelmDay
    ) -> Int {
        let weekDays = (0 ..< 7).map { history.weekStart.adding(days: $0) }
        let weekDaySet = Set(weekDays)
        return history.sessions.filter { weekDaySet.contains($0.helmDay) && $0.helmDay <= endDay }.count
    }

    static func familiarExerciseIDs(
        from history: PrescriptionHistory,
        withinDays days: Int = 90,
        referenceDate: Date = Date()
    ) -> Set<String> {
        let cutoff = referenceDate.addingTimeInterval(-Double(days) * 86_400)
        let ids = history.loggedSets
            .filter { $0.completedAt >= cutoff }
            .map(\.exerciseID)
        return Set(ids)
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

    /// Fingerprint of completed training this week; used to invalidate stale day-cache prescriptions.
    public static func historyFingerprint(
        _ history: PrescriptionHistory,
        through endDay: HelmDay,
        muscleMaps: [String: ExerciseMuscleMap],
        calendar: Calendar = .current
    ) -> String {
        let weekStart = history.weekStart
        let weekDays = Set((0 ..< 7).map { weekStart.adding(days: $0, calendar: calendar) })
        let weekSessions = history.sessions
            .filter { weekDays.contains($0.helmDay) && $0.helmDay <= endDay }
            .sorted { lhs, rhs in
                if lhs.helmDay != rhs.helmDay { return lhs.helmDay < rhs.helmDay }
                return lhs.startedAt < rhs.startedAt
            }

        let sessionTokens = weekSessions.map { session in
            let muscles = musclesTrained(in: session, muscleMaps: muscleMaps)
            let split = SessionSplitPlanner.inferSplitKind(from: muscles)?.rawValue ?? "custom"
            return "\(session.helmDay.formatted):\(split):\(session.sets.count)"
        }
        return "\(weekSessions.count)|\(sessionTokens.joined(separator: ";"))"
    }

    /// Build a week fingerprint from persisted history (for prescription cache invalidation).
    public static func historyFingerprint(
        from store: PersistenceStore,
        endingAt endDay: HelmDay,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) throws -> String {
        let history = try history(from: store, endingAt: endDay, calendar: calendar, cutoff: cutoff)
        let rows = try store.exercises.fetchCatalogRows()
        let familiar = familiarExerciseIDs(from: history)
        let catalog = PrescriptionCatalogBuilder.build(from: rows, familiarExerciseIDs: familiar)
        let muscleMaps = Dictionary(uniqueKeysWithValues: catalog.map { ($0.exerciseID, $0.muscleMap) })
        return historyFingerprint(history, through: endDay, muscleMaps: muscleMaps, calendar: calendar)
    }

    private static func musclesTrained(
        in session: WorkoutSession,
        muscleMaps: [String: ExerciseMuscleMap]
    ) -> Set<MuscleGroup> {
        var muscles = Set<MuscleGroup>()
        let exerciseIDs = Set(session.sets.map(\.exerciseID))
        for exerciseID in exerciseIDs {
            guard let map = muscleMaps[exerciseID] else { continue }
            for contribution in map.contributions where contribution.fraction >= 0.25 {
                muscles.insert(contribution.muscle)
            }
        }
        return muscles
    }
}
