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

/// Runtime view of week-scoped schedule overrides (pins, deferrals, forced rest).
public struct ScheduleWeekOverrides: Sendable, Equatable {
    public var pinnedByDay: [HelmDay: TrainingDayKind]
    public var deferredKinds: Set<TrainingDayKind>
    public var restDays: Set<HelmDay>
    public var reason: String?

    public init(
        pinnedByDay: [HelmDay: TrainingDayKind] = [:],
        deferredKinds: Set<TrainingDayKind> = [],
        restDays: Set<HelmDay> = [],
        reason: String? = nil
    ) {
        self.pinnedByDay = pinnedByDay
        self.deferredKinds = deferredKinds
        self.restDays = restDays
        self.reason = reason
    }

    public static let empty = ScheduleWeekOverrides()

    public var isEmpty: Bool {
        pinnedByDay.isEmpty && deferredKinds.isEmpty && restDays.isEmpty
    }

    public static func fromStored(
        _ stored: StoredScheduleOverrides,
        weekStart: HelmDay
    ) -> ScheduleWeekOverrides {
        guard stored.isActive(forWeekStarting: weekStart) else { return .empty }
        var pins: [HelmDay: TrainingDayKind] = [:]
        for (dayRaw, kindRaw) in stored.pinnedByDay {
            guard let day = HelmDay(formatted: dayRaw),
                  let kind = TrainingDayKind(rawValue: kindRaw)
            else { continue }
            pins[day] = kind
        }
        let deferred = Set(stored.deferredKinds.compactMap(TrainingDayKind.init(rawValue:)))
        let rest = Set(stored.restDays.compactMap(HelmDay.init(formatted:)))
        return ScheduleWeekOverrides(
            pinnedByDay: pins,
            deferredKinds: deferred,
            restDays: rest,
            reason: stored.reason
        )
    }
}

public enum SchedulePlanner {
    public static let defaultSessionsPerWeek = 3

    /// Muscles for a calendar day from a persisted planned-workout row, else the live schedule.
    public static func targetMuscles(
        for day: HelmDay,
        settings: StoredTrainingPlanSettings,
        history: PrescriptionHistory,
        muscleMaps: [String: ExerciseMuscleMap],
        plannedSessionJSON: String? = nil,
        calendar: Calendar = .current,
        overrides: ScheduleWeekOverrides = .empty
    ) -> [MuscleGroup] {
        if let json = plannedSessionJSON,
           let payload = PlannedWorkoutSessionDecoder.decode(from: json)
        {
            let fromPayload = payload.targetMuscles.compactMap(MuscleGroup.init(rawValue:))
            if !fromPayload.isEmpty {
                return fromPayload
            }
            if let kind = SessionSplitKind(rawValue: payload.splitKind), !kind.muscles.isEmpty {
                return kind.muscles
            }
        }

        return plan(
            for: day,
            emphasis: settings.phaseGoal.emphasis,
            history: history,
            muscleMaps: muscleMaps,
            calendar: calendar,
            sessionsPerWeek: settings.daysPerWeek,
            dayKindRotation: TrainingPlanShape.dayKindRotation(from: settings),
            overrides: overrides
        ).targetMuscles
    }

    public static func plan(
        for day: HelmDay,
        emphasis: String?,
        history: PrescriptionHistory,
        muscleMaps: [String: ExerciseMuscleMap],
        calendar: Calendar = .current,
        sessionsPerWeek: Int = defaultSessionsPerWeek,
        additionalCompletedSplits: [SessionSplitKind] = [],
        dayKindRotation: [TrainingDayKind] = [.push, .pull, .legs],
        overrides: ScheduleWeekOverrides = .empty
    ) -> SchedulePlanResult {
        _ = emphasis
        let rotation = dayKindRotation.isEmpty ? [.push, .pull, .legs] : dayKindRotation
        let loggedKinds = completedDayKinds(
            in: history,
            through: day,
            muscleMaps: muscleMaps,
            calendar: calendar,
            rotation: rotation
        )
        let additionalKinds = additionalCompletedSplits.map(\.trainingDayKind)
        let consumed = loggedKinds + additionalKinds

        let nextKind: TrainingDayKind
        if let pinned = overrides.pinnedByDay[day] {
            nextKind = pinned
        } else {
            nextKind = nextDayKind(
                rotation: rotation,
                consumed: consumed,
                skipKinds: overrides.deferredKinds
            )
        }
        let splitKind = SessionSplitKind(trainingDayKind: nextKind)

        var notes: [String] = []
        let isPinnedToday = overrides.pinnedByDay[day] != nil
        if let reason = overrides.reason, isPinnedToday {
            notes.append(reason)
        }
        if loggedKinds.isEmpty == false, consumed.count < rotation.count {
            let doneLabels = loggedKinds.map(\.label).joined(separator: ", ")
            notes.append("\(doneLabels) already logged this week - \(nextKind.label) is next.")
        }
        if consumed.count >= rotation.count {
            notes.append("Weekly split rotation complete - repeating \(splitKind.label) from schedule.")
        }
        if overrides.deferredKinds.isEmpty == false, isPinnedToday == false,
           overrides.deferredKinds.contains(nextKind) == false
        {
            let skipped = overrides.deferredKinds.map(\.label).sorted().joined(separator: ", ")
            notes.append("Deferred \(skipped) for recovery - \(nextKind.label) today.")
        }

        let completedCount = PrescriptionHistoryBuilder.completedSessionsThisWeek(in: history, through: day)
        if completedCount >= sessionsPerWeek {
            notes.append("Planned \(sessionsPerWeek) sessions this week are complete.")
        }

        return SchedulePlanResult(
            splitKind: splitKind,
            targetMuscles: nextKind.targetMuscles,
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
        avoidDays: Set<HelmDay> = [],
        dayKindRotation: [TrainingDayKind] = [.push, .pull, .legs],
        overrides: ScheduleWeekOverrides = .empty
    ) -> [PlannedWorkoutRecord] {
        var records: [PlannedWorkoutRecord] = []
        var plannedSplitsThisWeek: [SessionSplitKind] = []
        var plannedKindsThisWeek: [TrainingDayKind] = []
        var projectionWeekStart = PrescriptionHistoryBuilder.weekStart(containing: startDay, calendar: calendar)
        let placements = projectedTrainingDayPlacements(
            startingAt: startDay,
            dayCount: dayCount,
            sessionsPerWeek: sessionsPerWeek,
            history: history,
            calendar: calendar,
            avoidDays: avoidDays,
            overrides: overrides
        )

        for placement in placements {
            let day = placement.day
            let dayWeekStart = PrescriptionHistoryBuilder.weekStart(containing: day, calendar: calendar)
            if dayWeekStart != projectionWeekStart {
                plannedSplitsThisWeek = []
                plannedKindsThisWeek = []
                projectionWeekStart = dayWeekStart
            }

            let result = plan(
                for: day,
                emphasis: emphasis,
                history: history,
                muscleMaps: muscleMaps,
                calendar: calendar,
                sessionsPerWeek: sessionsPerWeek,
                additionalCompletedSplits: plannedSplitsThisWeek,
                dayKindRotation: dayKindRotation,
                overrides: overrides
            )
            plannedSplitsThisWeek.append(result.splitKind)
            plannedKindsThisWeek.append(result.splitKind.trainingDayKind)
            var notes = result.scheduleNotes
            if let ideal = placement.idealDay, ideal != day {
                // Keep override/recovery notes first for Week Ahead primaryNote.
                notes.append(
                    "Calendar busy on \(ideal.formatted) - session moved to \(day.formatted)."
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
        avoidDays: Set<HelmDay> = [],
        overrides: ScheduleWeekOverrides = .empty
    ) -> [HelmDay] {
        projectedTrainingDayPlacements(
            startingAt: startDay,
            dayCount: dayCount,
            sessionsPerWeek: sessionsPerWeek,
            history: history,
            calendar: calendar,
            avoidDays: avoidDays,
            overrides: overrides
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
        avoidDays: Set<HelmDay> = [],
        overrides: ScheduleWeekOverrides = .empty
    ) -> [TrainingDayPlacement] {
        let endDay = startDay.adding(days: dayCount - 1, calendar: calendar)
        let completedDays = Set(history.sessions.map(\.helmDay))
        let effectiveAvoid = avoidDays.union(overrides.restDays).union(completedDays)
        var placements: [TrainingDayPlacement] = []
        var usedDays = Set<HelmDay>()
        var weekStart = PrescriptionHistoryBuilder.weekStart(containing: startDay, calendar: calendar)

        // Force-pinned training days first, capped per ISO week against logged + quota.
        for day in overrides.pinnedByDay.keys.sorted(by: <) {
            guard day >= startDay, day <= endDay else { continue }
            guard overrides.restDays.contains(day) == false else { continue }
            guard completedDays.contains(day) == false else { continue }
            guard usedDays.contains(day) == false else { continue }

            let pinWeekStart = PrescriptionHistoryBuilder.weekStart(containing: day, calendar: calendar)
            let logged = loggedSessionsInWeek(
                history: history,
                weekStart: pinWeekStart,
                through: endDay,
                calendar: calendar
            )
            let pinnedAlready = placements.filter {
                PrescriptionHistoryBuilder.weekStart(containing: $0.day, calendar: calendar) == pinWeekStart
            }.count
            guard logged + pinnedAlready < sessionsPerWeek else { continue }

            placements.append(TrainingDayPlacement(day: day, idealDay: nil))
            usedDays.insert(day)
        }

        while weekStart <= endDay {
            let logged = loggedSessionsInWeek(
                history: history,
                weekStart: weekStart,
                through: endDay,
                calendar: calendar
            )
            var plannedInWeek = placements.filter {
                PrescriptionHistoryBuilder.weekStart(containing: $0.day, calendar: calendar) == weekStart
            }.count
            let weekEnd = weekStart.adding(days: 6, calendar: calendar)

            for offset in trainingDayOffsets(sessionsPerWeek: sessionsPerWeek) {
                guard sessionsPerWeek - logged - plannedInWeek > 0 else { break }

                let ideal = weekStart.adding(days: offset, calendar: calendar)
                guard ideal >= startDay, ideal <= endDay else { continue }
                guard overrides.restDays.contains(ideal) == false else { continue }
                guard completedDays.contains(ideal) == false else { continue }

                guard let placed = placeTrainingDay(
                    ideal: ideal,
                    startDay: startDay,
                    endDay: min(endDay, weekEnd),
                    avoidDays: effectiveAvoid,
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

        return placements.sorted { $0.day < $1.day }
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

    static func nextDayKind(
        rotation: [TrainingDayKind],
        consumed: [TrainingDayKind],
        skipKinds: Set<TrainingDayKind> = []
    ) -> TrainingDayKind {
        let cycle = rotation.isEmpty ? [.push, .pull, .legs] : rotation
        var remaining = cycle
        for kind in consumed {
            if let index = remaining.firstIndex(of: kind) {
                remaining.remove(at: index)
            } else if remaining.isEmpty == false {
                remaining.removeFirst()
            }
        }
        if let next = remaining.first(where: { !skipKinds.contains($0) }) {
            return next
        }
        if let next = cycle.first(where: { !skipKinds.contains($0) }) {
            return next
        }
        return cycle[consumed.count % cycle.count]
    }

    static func completedDayKinds(
        in history: PrescriptionHistory,
        through endDay: HelmDay,
        muscleMaps: [String: ExerciseMuscleMap],
        calendar: Calendar,
        rotation: [TrainingDayKind]
    ) -> [TrainingDayKind] {
        completedDayKindsByDay(
            in: history,
            through: endDay,
            muscleMaps: muscleMaps,
            calendar: calendar,
            rotation: rotation
        )
        .filter { $0.key <= endDay }
        .sorted { $0.key < $1.key }
        .map(\.value)
    }

    /// Logged day → inferred kind for the ISO week containing `endDay`.
    static func completedDayKindsByDay(
        in history: PrescriptionHistory,
        through endDay: HelmDay,
        muscleMaps: [String: ExerciseMuscleMap],
        calendar: Calendar,
        rotation: [TrainingDayKind]
    ) -> [HelmDay: TrainingDayKind] {
        let weekStart = PrescriptionHistoryBuilder.weekStart(containing: endDay, calendar: calendar)
        let weekDays = (0 ..< 7).map { weekStart.adding(days: $0, calendar: calendar) }
        let weekDaySet = Set(weekDays)
        var completed: [HelmDay: TrainingDayKind] = [:]

        for session in history.sessions where weekDaySet.contains(session.helmDay) && session.helmDay <= endDay {
            let muscleSet = musclesTrained(in: session, muscleMaps: muscleMaps)
            let among = rotation.isEmpty ? Array(TrainingDayKind.allCases) : rotation
            if let kind = TrainingDayKind.bestMatch(muscles: muscleSet, among: among) {
                completed[session.helmDay] = kind
            }
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
