import Core
import Foundation
import Persistence
import PlanKit

public struct SchedulePlanResult: Sendable, Equatable {
    public let splitKind: SessionSplitKind
    public let targetMuscles: [MuscleGroup]
    public let scheduleNotes: [String]

    public init(splitKind: SessionSplitKind, targetMuscles: [MuscleGroup], scheduleNotes: [String]) {
        self.splitKind = splitKind
        self.targetMuscles = targetMuscles
        self.scheduleNotes = scheduleNotes
    }
}

public enum SchedulePlanner {
    public static let defaultSessionsPerWeek = 3

    public static func plan(
        for day: HelmDay,
        emphasis: String?,
        history: PrescriptionHistory,
        muscleMaps: [String: ExerciseMuscleMap],
        calendar: Calendar = .current,
        sessionsPerWeek: Int = defaultSessionsPerWeek,
        additionalCompletedSplits: [SessionSplitKind] = []
    ) -> SchedulePlanResult {
        let rotation = SessionSplitPlanner.rotationSplits(emphasis: emphasis)

        let loggedSplits = completedSplitKinds(
            in: history,
            through: day,
            muscleMaps: muscleMaps,
            calendar: calendar
        )
        let completedSplits = completedSplitKinds(
            in: history,
            through: day,
            muscleMaps: muscleMaps,
            calendar: calendar,
            additionalCompletedSplits: additionalCompletedSplits
        )
        let pending = rotation.filter { !completedSplits.contains($0) }
        var notes: [String] = []

        let splitKind: SessionSplitKind
        if let next = pending.first {
            splitKind = next
            if loggedSplits.isEmpty == false, pending.count < rotation.count {
                let doneLabels = loggedSplits.map(\.label).joined(separator: ", ")
                notes.append("\(doneLabels) already logged this week - \(next.label) is next.")
            }
        } else {
            splitKind = SessionSplitPlanner.splitKind(for: day, emphasis: emphasis, calendar: calendar)
            notes.append("Weekly split rotation complete - repeating \(splitKind.label) from schedule.")
        }

        let completedCount = PrescriptionHistoryBuilder.completedSessionsThisWeek(in: history, through: day)
        if completedCount >= sessionsPerWeek {
            notes.append("Planned \(sessionsPerWeek) sessions this week are complete.")
        }

        return SchedulePlanResult(
            splitKind: splitKind,
            targetMuscles: splitKind.muscles,
            scheduleNotes: notes
        )
    }

    public static func plannedWorkoutRecords(
        startingAt startDay: HelmDay,
        dayCount: Int,
        emphasis: String?,
        history: PrescriptionHistory,
        muscleMaps: [String: ExerciseMuscleMap],
        calendar: Calendar = .current,
        sessionsPerWeek: Int = defaultSessionsPerWeek,
        avoidDays: Set<HelmDay> = []
    ) -> [PlannedWorkoutRecord] {
        var records: [PlannedWorkoutRecord] = []
        var plannedSplitsThisWeek: [SessionSplitKind] = []
        var projectionWeekStart = PrescriptionHistoryBuilder.weekStart(containing: startDay, calendar: calendar)
        let placements = projectedTrainingDayPlacements(
            startingAt: startDay,
            dayCount: dayCount,
            sessionsPerWeek: sessionsPerWeek,
            history: history,
            calendar: calendar,
            avoidDays: avoidDays
        )

        for placement in placements {
            let day = placement.day
            let dayWeekStart = PrescriptionHistoryBuilder.weekStart(containing: day, calendar: calendar)
            if dayWeekStart != projectionWeekStart {
                plannedSplitsThisWeek = []
                projectionWeekStart = dayWeekStart
            }

            let result = plan(
                for: day,
                emphasis: emphasis,
                history: history,
                muscleMaps: muscleMaps,
                calendar: calendar,
                sessionsPerWeek: sessionsPerWeek,
                additionalCompletedSplits: plannedSplitsThisWeek
            )
            plannedSplitsThisWeek.append(result.splitKind)
            var notes = result.scheduleNotes
            if let ideal = placement.idealDay, ideal != day {
                notes.insert(
                    "Calendar busy on \(ideal.formatted) - session moved to \(day.formatted).",
                    at: 0
                )
            }
            let payload = PlannedWorkoutSessionPayload(
                splitLabel: result.splitKind.label,
                splitKind: result.splitKind.rawValue,
                targetMuscles: result.targetMuscles.map(\.rawValue),
                scheduleNotes: notes
            )
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(payload),
                  let json = String(data: data, encoding: .utf8)
            else {
                continue
            }
            records.append(
                PlannedWorkoutRecord(
                    id: "planned-\(day.formatted)",
                    helmDay: day,
                    status: "pending",
                    trainingLoad: Double(result.targetMuscles.count),
                    sessionJSON: json
                )
            )
        }
        return records
    }

    static func trainingDayOffsets(sessionsPerWeek: Int, daysInWeek: Int = 7) -> [Int] {
        guard sessionsPerWeek > 0 else { return [] }
        guard sessionsPerWeek < daysInWeek else { return Array(0 ..< daysInWeek) }
        return (0 ..< sessionsPerWeek).map { index in
            (index * daysInWeek) / sessionsPerWeek
        }
    }

    static func projectedTrainingDays(
        startingAt startDay: HelmDay,
        dayCount: Int,
        sessionsPerWeek: Int,
        history: PrescriptionHistory,
        calendar: Calendar,
        avoidDays: Set<HelmDay> = []
    ) -> [HelmDay] {
        projectedTrainingDayPlacements(
            startingAt: startDay,
            dayCount: dayCount,
            sessionsPerWeek: sessionsPerWeek,
            history: history,
            calendar: calendar,
            avoidDays: avoidDays
        ).map(\.day)
    }

    struct TrainingDayPlacement: Equatable {
        let day: HelmDay
        /// Ideal offset day before calendar avoidance. Nil when ideal was already free.
        let idealDay: HelmDay?
    }

    static func projectedTrainingDayPlacements(
        startingAt startDay: HelmDay,
        dayCount: Int,
        sessionsPerWeek: Int,
        history: PrescriptionHistory,
        calendar: Calendar,
        avoidDays: Set<HelmDay> = []
    ) -> [TrainingDayPlacement] {
        let endDay = startDay.adding(days: dayCount - 1, calendar: calendar)
        var placements: [TrainingDayPlacement] = []
        var usedDays = Set<HelmDay>()
        var weekStart = PrescriptionHistoryBuilder.weekStart(containing: startDay, calendar: calendar)

        while weekStart <= endDay, placements.count < sessionsPerWeek {
            let logged = loggedSessionsInWeek(
                history: history,
                weekStart: weekStart,
                through: endDay,
                calendar: calendar
            )
            var plannedInWeek = 0
            let weekEnd = weekStart.adding(days: 6, calendar: calendar)

            for offset in trainingDayOffsets(sessionsPerWeek: sessionsPerWeek) {
                guard placements.count < sessionsPerWeek else { break }
                guard sessionsPerWeek - logged - plannedInWeek > 0 else { break }

                let ideal = weekStart.adding(days: offset, calendar: calendar)
                guard ideal >= startDay, ideal <= endDay else { continue }

                guard let placed = placeTrainingDay(
                    ideal: ideal,
                    startDay: startDay,
                    endDay: min(endDay, weekEnd),
                    avoidDays: avoidDays,
                    usedDays: usedDays
                ) else {
                    continue
                }

                placements.append(
                    TrainingDayPlacement(
                        day: placed,
                        idealDay: placed == ideal ? nil : ideal
                    )
                )
                usedDays.insert(placed)
                plannedInWeek += 1
            }

            weekStart = weekStart.adding(days: 7, calendar: calendar)
        }

        return placements
    }

    /// Prefer ideal day; if busy or taken, slide forward then backward within the week window.
    private static func placeTrainingDay(
        ideal: HelmDay,
        startDay: HelmDay,
        endDay: HelmDay,
        avoidDays: Set<HelmDay>,
        usedDays: Set<HelmDay>
    ) -> HelmDay? {
        func isFree(_ day: HelmDay) -> Bool {
            day >= startDay
                && day <= endDay
                && !avoidDays.contains(day)
                && !usedDays.contains(day)
        }

        if isFree(ideal) {
            return ideal
        }

        var cursor = ideal.adding(days: 1)
        while cursor <= endDay {
            if isFree(cursor) {
                return cursor
            }
            cursor = cursor.adding(days: 1)
        }

        cursor = ideal.adding(days: -1)
        while cursor >= startDay {
            if isFree(cursor) {
                return cursor
            }
            cursor = cursor.adding(days: -1)
        }

        return nil
    }

    private static func loggedSessionsInWeek(
        history: PrescriptionHistory,
        weekStart: HelmDay,
        through endDay: HelmDay,
        calendar: Calendar
    ) -> Int {
        let weekDays = (0 ..< 7).map { weekStart.adding(days: $0, calendar: calendar) }
        let weekDaySet = Set(weekDays)
        return history.sessions.filter { weekDaySet.contains($0.helmDay) && $0.helmDay <= endDay }.count
    }

    private static func completedSplitKinds(
        in history: PrescriptionHistory,
        through endDay: HelmDay,
        muscleMaps: [String: ExerciseMuscleMap],
        calendar: Calendar,
        additionalCompletedSplits: [SessionSplitKind] = []
    ) -> [SessionSplitKind] {
        let weekStart = PrescriptionHistoryBuilder.weekStart(containing: endDay, calendar: calendar)
        let weekDays = (0 ..< 7).map { weekStart.adding(days: $0, calendar: calendar) }
        let weekDaySet = Set(weekDays)
        var completed: [SessionSplitKind] = []

        for session in history.sessions where weekDaySet.contains(session.helmDay) && session.helmDay <= endDay {
            let muscleSet = musclesTrained(in: session, muscleMaps: muscleMaps)
            if let kind = SessionSplitPlanner.inferSplitKind(from: muscleSet), !completed.contains(kind) {
                completed.append(kind)
            }
        }

        for split in additionalCompletedSplits where !completed.contains(split) {
            completed.append(split)
        }

        return completed
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

public struct PlannedWorkoutSessionPayload: Codable, Sendable {
    public let splitLabel: String
    public let splitKind: String
    public let targetMuscles: [String]
    public let scheduleNotes: [String]

    public init(
        splitLabel: String,
        splitKind: String,
        targetMuscles: [String],
        scheduleNotes: [String]
    ) {
        self.splitLabel = splitLabel
        self.splitKind = splitKind
        self.targetMuscles = targetMuscles
        self.scheduleNotes = scheduleNotes
    }

    public var primaryNote: String? {
        scheduleNotes.first
    }
}

public enum PlannedWorkoutSessionDecoder {
    public static func decode(from sessionJSON: String) -> PlannedWorkoutSessionPayload? {
        guard let data = sessionJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PlannedWorkoutSessionPayload.self, from: data)
    }
}
