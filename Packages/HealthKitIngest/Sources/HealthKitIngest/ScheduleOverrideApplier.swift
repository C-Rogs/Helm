import CoachLLM
import Core
import Foundation
import Persistence
import PlanKit

/// Applies coach schedule negotiations onto week-scoped overrides, then re-plans.
public enum ScheduleOverrideApplier {
    public static func apply(
        _ payload: ScheduleAdjustmentPayload,
        persistence: PersistenceStore,
        today: HelmDay,
        calendar: Calendar = .current
    ) throws {
        if try hasLiveWorkout(persistence: persistence), affectsToday(payload, today: today) {
            throw ScheduleOverrideApplyError.liveWorkoutActive
        }

        let weekStart = PrescriptionHistoryBuilder.weekStart(containing: today, calendar: calendar)
        var stored = (try? persistence.scheduleOverrides.load()) ?? .empty
        if stored.isActive(forWeekStarting: weekStart) == false {
            stored = StoredScheduleOverrides(weekStartFormatted: weekStart.formatted)
        } else {
            stored.weekStartFormatted = weekStart.formatted
        }

        switch payload.action {
        case .clear:
            try persistence.scheduleOverrides.clear()
            return

        case .deferKinds:
            let settings = try persistence.trainingPlan.load()
            let rotation = TrainingPlanShape.dayKindRotation(from: settings)
            // Replace deferred set for this negotiation (do not silently stack forever).
            var deferred = Set<TrainingDayKind>()
            if let kinds = payload.kinds {
                for raw in kinds {
                    if let kind = parseKind(raw) {
                        deferred.insert(kind)
                    }
                }
            }
            if let region = payload.region, region.isEmpty == false {
                for kind in TrainingDayRecoveryMap.deferredKinds(forRegion: region, among: rotation) {
                    deferred.insert(kind)
                }
            }
            guard deferred.isEmpty == false || payload.pinKind != nil else {
                throw ScheduleOverrideApplyError.missingDeferTarget
            }
            stored.deferredKinds = deferred.map(\.rawValue).sorted()
            let deferredLabels = deferred.map(\.label).sorted().joined(separator: "/")
            stored.reason = payload.reason
                ?? (payload.region.map { "Recovering \($0); skip \(deferredLabels)" }
                    ?? "Skip \(deferredLabels) for recovery")

            let pinDay = resolvePinDay(
                payloadHelmDay: payload.helmDay,
                today: today,
                weekStart: weekStart,
                calendar: calendar,
                persistence: persistence,
                settings: settings,
                stored: stored
            )
            if let explicit = payload.pinKind.flatMap(parseKind) {
                guard deferred.contains(explicit) == false else {
                    throw ScheduleOverrideApplyError.pinConflictsDeferred(explicit.label)
                }
                stored.pinnedByDay[pinDay.formatted] = explicit.rawValue
                stored.restDays.removeAll { $0 == pinDay.formatted }
            } else if let preferred = preferredKind(
                persistence: persistence,
                today: today,
                rotation: rotation,
                deferred: deferred,
                calendar: calendar
            ) {
                stored.pinnedByDay[pinDay.formatted] = preferred.rawValue
                stored.restDays.removeAll { $0 == pinDay.formatted }
            }

        case .pinDay:
            let day = parseDay(payload.helmDay) ?? today
            guard let kind = payload.pinKind.flatMap(parseKind) else {
                throw ScheduleOverrideApplyError.missingPinKind
            }
            try validateDayInScheduleWindow(day, today: today, weekStart: weekStart, calendar: calendar)
            if try loggedKind(on: day, persistence: persistence, calendar: calendar) != nil {
                throw ScheduleOverrideApplyError.dayAlreadyLogged(day.formatted)
            }
            stored.pinnedByDay[day.formatted] = kind.rawValue
            stored.restDays.removeAll { $0 == day.formatted }
            // Pinning a deferred kind means athlete overruled the defer for that day.
            stored.deferredKinds.removeAll { $0 == kind.rawValue }
            stored.reason = payload.reason ?? "Pinned \(kind.label) on \(day.formatted)"

        case .swapDays:
            let dayA = parseDay(payload.dayA)
            let dayB = parseDay(payload.dayB)
            guard let dayA, let dayB else {
                throw ScheduleOverrideApplyError.missingSwapDays
            }
            guard dayA != dayB else {
                throw ScheduleOverrideApplyError.swapSameDay
            }
            try validateDayInScheduleWindow(dayA, today: today, weekStart: weekStart, calendar: calendar)
            try validateDayInScheduleWindow(dayB, today: today, weekStart: weekStart, calendar: calendar)
            try applySwap(
                dayA: dayA,
                dayB: dayB,
                stored: &stored,
                persistence: persistence,
                today: today,
                weekStart: weekStart,
                calendar: calendar
            )
            stored.reason = payload.reason ?? "Swapped \(dayA.formatted) and \(dayB.formatted)"
        }

        try persistence.scheduleOverrides.save(stored)
    }

    // MARK: - Swap / kind resolution

    /// Effective day → kind map for the ISO week (planner + logged history).
    public static func resolveKindByDay(
        persistence: PersistenceStore,
        today: HelmDay,
        weekStart: HelmDay,
        calendar: Calendar,
        stored: StoredScheduleOverrides
    ) throws -> [HelmDay: TrainingDayKind?] {
        let settings = try persistence.trainingPlan.load()
        let rotation = TrainingPlanShape.dayKindRotation(from: settings)
        let history = try PrescriptionHistoryBuilder.history(
            from: persistence,
            endingAt: today.adding(days: 6, calendar: calendar),
            calendar: calendar
        )
        let catalogRows = (try? persistence.exercises.fetchCatalogRows()) ?? []
        let familiar = PrescriptionHistoryBuilder.familiarExerciseIDs(from: history)
        let catalog = PrescriptionCatalogBuilder.build(
            from: catalogRows,
            familiarExerciseIDs: familiar
        )
        let muscleMaps = Dictionary(uniqueKeysWithValues: catalog.map {
            ($0.exerciseID, $0.muscleMap)
        })
        let overrides = ScheduleWeekOverrides.fromStored(stored, weekStart: weekStart)
        let weekEnd = weekStart.adding(days: 6, calendar: calendar)
        let dayCount = max(1, weekStart.days(to: weekEnd, calendar: calendar) + 1)

        let projected = SchedulePlanner.plannedWorkoutRecords(
            startingAt: weekStart,
            dayCount: dayCount,
            emphasis: settings.phaseGoal.emphasis,
            history: history,
            muscleMaps: muscleMaps,
            calendar: calendar,
            sessionsPerWeek: settings.daysPerWeek,
            dayKindRotation: rotation,
            overrides: overrides
        )

        var kindByDay: [HelmDay: TrainingDayKind?] = [:]
        for offset in 0 ..< 7 {
            let day = weekStart.adding(days: offset, calendar: calendar)
            kindByDay[day] = nil
        }
        for record in projected {
            let day = try record.decodedHelmDay()
            if let payload = PlannedWorkoutSessionDecoder.decode(from: record.sessionJSON) {
                let kind = TrainingDayKind(rawValue: payload.splitKind)
                    ?? SessionSplitKind(rawValue: payload.splitKind)?.trainingDayKind
                kindByDay[day] = kind
            }
        }

        // Logged sessions win over projection (Done days).
        let logged = SchedulePlanner.completedDayKindsByDay(
            in: history,
            through: weekEnd,
            muscleMaps: muscleMaps,
            calendar: calendar,
            rotation: rotation
        )
        for (day, kind) in logged {
            kindByDay[day] = kind
        }

        for (raw, kindRaw) in stored.pinnedByDay {
            guard let day = HelmDay(formatted: raw), let kind = TrainingDayKind(rawValue: kindRaw) else { continue }
            if logged[day] == nil {
                kindByDay[day] = kind
            }
        }
        for rest in stored.restDays {
            if let day = HelmDay(formatted: rest), logged[day] == nil {
                kindByDay[day] = nil
            }
        }

        return kindByDay
    }

    private static func applySwap(
        dayA: HelmDay,
        dayB: HelmDay,
        stored: inout StoredScheduleOverrides,
        persistence: PersistenceStore,
        today: HelmDay,
        weekStart: HelmDay,
        calendar: Calendar
    ) throws {
        let kindByDay = try resolveKindByDay(
            persistence: persistence,
            today: today,
            weekStart: weekStart,
            calendar: calendar,
            stored: stored
        )
        let kindA = kindByDay[dayA] ?? nil
        let kindB = kindByDay[dayB] ?? nil
        let loggedA = try loggedKind(on: dayA, persistence: persistence, calendar: calendar)
        let loggedB = try loggedKind(on: dayB, persistence: persistence, calendar: calendar)

        if loggedA != nil, loggedB != nil {
            throw ScheduleOverrideApplyError.bothDaysLogged
        }
        // Do not move a completed session off its day; only move the open slot onto/off rest.
        if loggedA != nil, kindB != nil {
            throw ScheduleOverrideApplyError.cannotMoveLoggedDay(dayA.formatted)
        }
        if loggedB != nil, kindA != nil {
            throw ScheduleOverrideApplyError.cannotMoveLoggedDay(dayB.formatted)
        }

        func set(day: HelmDay, kind: TrainingDayKind?, allowOverwriteLogged: Bool) throws {
            if !allowOverwriteLogged, try loggedKind(on: day, persistence: persistence, calendar: calendar) != nil {
                return
            }
            let key = day.formatted
            if let kind {
                stored.pinnedByDay[key] = kind.rawValue
                stored.restDays.removeAll { $0 == key }
            } else {
                stored.pinnedByDay.removeValue(forKey: key)
                if stored.restDays.contains(key) == false {
                    stored.restDays.append(key)
                }
            }
        }

        if loggedA != nil {
            // A done, B open: keep logged day; clear the open day to Rest.
            try set(day: dayB, kind: nil, allowOverwriteLogged: false)
        } else if loggedB != nil {
            try set(day: dayA, kind: nil, allowOverwriteLogged: false)
        } else {
            try set(day: dayA, kind: kindB, allowOverwriteLogged: false)
            try set(day: dayB, kind: kindA, allowOverwriteLogged: false)
        }
    }

    // MARK: - Helpers

    private static func resolvePinDay(
        payloadHelmDay: String?,
        today: HelmDay,
        weekStart: HelmDay,
        calendar: Calendar,
        persistence: PersistenceStore,
        settings: StoredTrainingPlanSettings,
        stored: StoredScheduleOverrides
    ) -> HelmDay {
        if let explicit = parseDay(payloadHelmDay) {
            return explicit
        }
        // Prefer today when it is not already logged; else first upcoming free day in week.
        if (try? loggedKind(on: today, persistence: persistence, calendar: calendar)) == nil {
            return today
        }
        let weekEnd = weekStart.adding(days: 6, calendar: calendar)
        var cursor = today.adding(days: 1, calendar: calendar)
        while cursor <= weekEnd {
            if (try? loggedKind(on: cursor, persistence: persistence, calendar: calendar)) == nil,
               stored.restDays.contains(cursor.formatted) == false
            {
                return cursor
            }
            cursor = cursor.adding(days: 1, calendar: calendar)
        }
        return today
    }

    private static func preferredKind(
        persistence: PersistenceStore,
        today: HelmDay,
        rotation: [TrainingDayKind],
        deferred: Set<TrainingDayKind>,
        calendar: Calendar
    ) -> TrainingDayKind? {
        let history = (try? PrescriptionHistoryBuilder.history(
            from: persistence,
            endingAt: today,
            calendar: calendar
        ))
        let consumed: [TrainingDayKind]
        if let history {
            let catalogRows = (try? persistence.exercises.fetchCatalogRows()) ?? []
            let familiar = PrescriptionHistoryBuilder.familiarExerciseIDs(from: history)
            let catalog = PrescriptionCatalogBuilder.build(
                from: catalogRows,
                familiarExerciseIDs: familiar
            )
            let muscleMaps = Dictionary(uniqueKeysWithValues: catalog.map {
                ($0.exerciseID, $0.muscleMap)
            })
            consumed = SchedulePlanner.completedDayKinds(
                in: history,
                through: today,
                muscleMaps: muscleMaps,
                calendar: calendar,
                rotation: rotation
            )
        } else {
            consumed = []
        }
        return TrainingDayRecoveryMap.preferredKind(
            rotation: rotation,
            deferred: deferred,
            consumed: consumed
        )
    }

    private static func loggedKind(
        on day: HelmDay,
        persistence: PersistenceStore,
        calendar: Calendar
    ) throws -> TrainingDayKind? {
        let history = try PrescriptionHistoryBuilder.history(
            from: persistence,
            endingAt: day,
            calendar: calendar
        )
        guard history.sessions.contains(where: { $0.helmDay == day }) else { return nil }
        let settings = try persistence.trainingPlan.load()
        let rotation = TrainingPlanShape.dayKindRotation(from: settings)
        let catalogRows = (try? persistence.exercises.fetchCatalogRows()) ?? []
        let familiar = PrescriptionHistoryBuilder.familiarExerciseIDs(from: history)
        let catalog = PrescriptionCatalogBuilder.build(
            from: catalogRows,
            familiarExerciseIDs: familiar
        )
        let muscleMaps = Dictionary(uniqueKeysWithValues: catalog.map {
            ($0.exerciseID, $0.muscleMap)
        })
        let byDay = SchedulePlanner.completedDayKindsByDay(
            in: history,
            through: day,
            muscleMaps: muscleMaps,
            calendar: calendar,
            rotation: rotation
        )
        return byDay[day]
    }

    private static func validateDayInScheduleWindow(
        _ day: HelmDay,
        today: HelmDay,
        weekStart: HelmDay,
        calendar: Calendar
    ) throws {
        // Allow current ISO week (Mon-Sun) and the Week Ahead strip (today -> +6),
        // which can spill into next week (same window coach sees).
        let weekEnd = weekStart.adding(days: 6, calendar: calendar)
        let horizonEnd = today.adding(days: 6, calendar: calendar)
        let windowStart = min(weekStart, today)
        let windowEnd = max(weekEnd, horizonEnd)
        guard day >= windowStart, day <= windowEnd else {
            throw ScheduleOverrideApplyError.dayOutsideWeek(day.formatted)
        }
    }

    private static func hasLiveWorkout(persistence: PersistenceStore) throws -> Bool {
        try persistence.activeSessions.fetchActiveSnapshot(at: Date()) != nil
    }

    private static func affectsToday(_ payload: ScheduleAdjustmentPayload, today: HelmDay) -> Bool {
        switch payload.action {
        case .clear:
            return true
        case .deferKinds:
            let pin = parseDay(payload.helmDay) ?? today
            return pin == today
        case .pinDay:
            return (parseDay(payload.helmDay) ?? today) == today
        case .swapDays:
            return parseDay(payload.dayA) == today || parseDay(payload.dayB) == today
        }
    }

    private static func parseKind(_ raw: String) -> TrainingDayKind? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let direct = TrainingDayKind(rawValue: trimmed) { return direct }
        switch trimmed {
        case "push day", "push": return .push
        case "pull day", "pull": return .pull
        case "leg day", "legs", "leg": return .legs
        case "upper", "upper day": return .upper
        case "lower", "lower day": return .lower
        case "full", "full body", "full_body": return .full
        case "arms", "arm", "arm day": return .arms
        default: return nil
        }
    }

    private static func parseDay(_ raw: String?) -> HelmDay? {
        guard let raw, raw.isEmpty == false else { return nil }
        return HelmDay(formatted: raw)
    }
}

public enum ScheduleOverrideApplyError: Error, LocalizedError {
    case missingPinKind
    case missingSwapDays
    case missingDeferTarget
    case swapSameDay
    case dayOutsideWeek(String)
    case dayAlreadyLogged(String)
    case bothDaysLogged
    case cannotMoveLoggedDay(String)
    case liveWorkoutActive
    case pinConflictsDeferred(String)

    public var errorDescription: String? {
        switch self {
        case .missingPinKind:
            "schedule_adjustment pin_day needs pinKind"
        case .missingSwapDays:
            "schedule_adjustment swap_days needs dayA and dayB"
        case .missingDeferTarget:
            "schedule_adjustment defer_kinds needs region or kinds"
        case .swapSameDay:
            "Cannot swap a day with itself"
        case let .dayOutsideWeek(day):
            "\(day) is outside this week's schedule window"
        case let .dayAlreadyLogged(day):
            "\(day) already has a logged session"
        case .bothDaysLogged:
            "Both days are already logged"
        case let .cannotMoveLoggedDay(day):
            "Cannot move logged session on \(day)"
        case .liveWorkoutActive:
            "Finish or discard the live workout before changing today's schedule"
        case let .pinConflictsDeferred(kind):
            "Cannot pin \(kind) while it is deferred for recovery"
        }
    }
}
