import Core
import Foundation
import Persistence
import PlanKit

/// Applies runtime drift resolution when logged sessions diverge from projected calendar.
enum ScheduleDriftResolver {
    static func resolveAndApply(
        records: [PlannedWorkoutRecord],
        history: PrescriptionHistory,
        muscleMaps: [String: ExerciseMuscleMap],
        calendar: Calendar = Calendar(identifier: .iso8601)
    ) -> (records: [PlannedWorkoutRecord], driftNotes: [String]) {
        guard !records.isEmpty else { return (records, []) }

        var calendarState = PlannedCalendar(
            sessions: records.map { record in
                PlannedSession(
                    id: record.id,
                    plannedDay: decodeHelmDay(from: record) ?? history.weekStart,
                    status: PlannedSessionStatus(rawValue: record.status) ?? .pending,
                    trainingLoad: record.trainingLoad
                )
            }
        )

        let dailyLoads = dailyTrainingLoads(from: history, muscleMaps: muscleMaps)
        let completedLogs = matchCompletedSessionsToPlanned(
            history: history,
            records: records,
            muscleMaps: muscleMaps,
            calendar: calendar
        )

        var driftNotes: [String] = []
        for log in completedLogs {
            let adjustment = PlanKit.resolveDrift(
                planned: calendarState,
                actual: ActualCalendar(dailyLoadByDay: dailyLoads, completedLog: log),
                calendar: calendar
            )
            calendarState = adjustment.updatedCalendar
            driftNotes.append(contentsOf: resolutionNotes(adjustment.resolutions, calendar: calendar))
        }

        let updatedRecords = records.map { record -> PlannedWorkoutRecord in
            guard let session = calendarState.sessions.first(where: { $0.id == record.id }) else {
                return record
            }
            var updated = record
            updated.status = session.status.rawValue
            updated.trainingLoad = session.trainingLoad
            if let payload = PlannedWorkoutSessionDecoder.decode(from: record.sessionJSON) {
                var notes = payload.scheduleNotes
                let dayNotes = driftNotes.filter { note in
                    note.contains(decodeHelmDay(from: record)?.formatted ?? "") ||
                        note.contains(session.plannedDay.formatted)
                }
                for note in dayNotes where !notes.contains(note) {
                    notes.append(note)
                }
                let encoder = JSONEncoder()
                if let data = try? encoder.encode(
                    PlannedWorkoutSessionPayload(
                        splitLabel: payload.splitLabel,
                        splitKind: payload.splitKind,
                        targetMuscles: payload.targetMuscles,
                        scheduleNotes: notes
                    )
                ), let json = String(data: data, encoding: .utf8) {
                    updated.sessionJSON = json
                }
            }
            if session.plannedDay.formatted != record.id.replacingOccurrences(of: "planned-", with: "") {
                // Keep record id anchored to original projection; status captures drift.
            }
            return updated
        }

        return (updatedRecords, driftNotes)
    }

    private static func matchCompletedSessionsToPlanned(
        history: PrescriptionHistory,
        records: [PlannedWorkoutRecord],
        muscleMaps: [String: ExerciseMuscleMap],
        calendar: Calendar
    ) -> [ActualSessionLog] {
        var logs: [ActualSessionLog] = []
        var claimedPlannedIDs = Set<String>()

        let weekStart = history.weekStart
        let weekDays = Set((0 ..< 7).map { weekStart.adding(days: $0, calendar: calendar) })
        let weekSessions = history.sessions
            .filter { weekDays.contains($0.helmDay) }
            .sorted { $0.startedAt < $1.startedAt }

        let plannedKinds = records.compactMap { row -> SessionSplitKind? in
            guard let json = PlannedWorkoutSessionDecoder.decode(from: row.sessionJSON) else {
                return nil
            }
            return SessionSplitKind(rawValue: json.splitKind)
        }

        for session in weekSessions {
            let muscles = musclesTrained(in: session, muscleMaps: muscleMaps)
            let inferred = SessionSplitPlanner.inferSplitKind(from: muscles, among: plannedKinds)
                ?? SessionSplitPlanner.inferSplitKind(from: muscles)
            guard let inferred else { continue }

            let candidate = records.first { record in
                guard !claimedPlannedIDs.contains(record.id) else { return false }
                guard let payload = PlannedWorkoutSessionDecoder.decode(from: record.sessionJSON) else {
                    return false
                }
                guard payload.splitKind == inferred.rawValue else { return false }
                let status = PlannedSessionStatus(rawValue: record.status) ?? .pending
                return status == .pending || status == .shifted
            } ?? records.first { record in
                guard !claimedPlannedIDs.contains(record.id) else { return false }
                guard let payload = PlannedWorkoutSessionDecoder.decode(from: record.sessionJSON) else {
                    return false
                }
                return payload.splitKind == inferred.rawValue
            }

            guard let candidate else { continue }
            claimedPlannedIDs.insert(candidate.id)
            logs.append(
                ActualSessionLog(
                    id: session.id.uuidString,
                    plannedSessionID: candidate.id,
                    actualDay: session.helmDay,
                    trainingLoad: Double(muscles.count)
                )
            )
        }

        return logs
    }

    private static func dailyTrainingLoads(
        from history: PrescriptionHistory,
        muscleMaps: [String: ExerciseMuscleMap]
    ) -> [HelmDay: Double] {
        var loads: [HelmDay: Double] = [:]
        let context = PlanKit.hardSetEvaluationContext(from: history.sessions)
        for session in history.sessions {
            let hardSets = session.sets.filter { PlanKit.stimulusCredit($0, context: context) > 0 }.count
            loads[session.helmDay, default: 0] += Double(hardSets)
        }
        return loads
    }

    private static func musclesTrained(
        in session: WorkoutSession,
        muscleMaps: [String: ExerciseMuscleMap]
    ) -> Set<MuscleGroup> {
        var muscles = Set<MuscleGroup>()
        for exerciseID in Set(session.sets.map(\.exerciseID)) {
            guard let map = muscleMaps[exerciseID] else { continue }
            for contribution in map.contributions where contribution.fraction >= 0.25 {
                muscles.insert(contribution.muscle)
            }
        }
        return muscles
    }

    private static func decodeHelmDay(from record: PlannedWorkoutRecord) -> HelmDay? {
        let prefix = "planned-"
        guard record.id.hasPrefix(prefix) else { return nil }
        let suffix = String(record.id.dropFirst(prefix.count))
        let parts = suffix.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else {
            return nil
        }
        return HelmDay(year: year, month: month, day: day)
    }

    private static func resolutionNotes(
        _ resolutions: [SessionDriftResolution],
        calendar: Calendar
    ) -> [String] {
        resolutions.compactMap { resolution in
            switch resolution.action {
            case .keep:
                return nil
            case .shift:
                if let toDay = resolution.toDay, toDay != resolution.fromDay {
                    return "Session drifted from \(resolution.fromDay.formatted) to \(toDay.formatted)."
                }
                return "Session shifted to match logged day."
            case .skip:
                return "Missed session on \(resolution.fromDay.formatted) - skipped."
            case .restructure:
                if let toDay = resolution.toDay {
                    return "Late completion on \(toDay.formatted) - week restructured."
                }
                return "Week restructured after late completion."
            }
        }
    }
}
