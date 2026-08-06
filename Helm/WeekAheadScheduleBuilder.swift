import Core
import DesignSystem
import Foundation
import HealthKitIngest
import Persistence
import PlanKit

enum WeekAheadScheduleBuilder {
    static let horizonDays = 7

    static func build(
        store: PersistenceStore,
        today: HelmDay,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default,
        busyDayHints: [HelmDay: String] = [:]
    ) throws -> WeekAheadScheduleModel {
        let endDay = today.adding(days: horizonDays - 1, calendar: calendar)
        let records = try store.plan.fetchPlannedWorkouts(from: today, through: endDay)
        let recordsByDay = Dictionary(
            uniqueKeysWithValues: try records.map { record in
                (try record.decodedHelmDay(), record)
            }
        )

        let history = try PrescriptionHistoryBuilder.history(
            from: store,
            endingAt: endDay,
            calendar: calendar,
            cutoff: cutoff
        )
        let completedDays = Set(history.sessions.map(\.helmDay))

        var rows: [WeekAheadScheduleRow] = []
        for offset in 0 ..< horizonDays {
            let helmDay = today.adding(days: offset, calendar: calendar)
            if let record = recordsByDay[helmDay] {
                let payload = PlannedWorkoutSessionDecoder.decode(from: record.sessionJSON)
                let splitLabel = payload?.splitLabel ?? "Session"
                let note = payload?.primaryNote
                let status = resolvedStatus(
                    storedStatus: record.status,
                    helmDay: helmDay,
                    today: today,
                    completedDays: completedDays
                )
                rows.append(
                    WeekAheadScheduleRow(
                        id: helmDay.formatted,
                        dayLabel: dayLabel(for: helmDay, today: today, calendar: calendar),
                        splitLabel: splitLabel,
                        note: note,
                        status: status,
                        driftNote: driftNote(for: record, helmDay: helmDay, calendar: calendar),
                        busyDayHint: busyDayHints[helmDay],
                        isToday: helmDay == today
                    )
                )
            } else {
                rows.append(
                    WeekAheadScheduleRow(
                        id: helmDay.formatted,
                        dayLabel: dayLabel(for: helmDay, today: today, calendar: calendar),
                        splitLabel: "Rest",
                        note: nil,
                        status: .rest,
                        driftNote: nil,
                        busyDayHint: busyDayHints[helmDay],
                        isToday: helmDay == today
                    )
                )
            }
        }

        return WeekAheadScheduleModel(rows: rows)
    }

    private static func resolvedStatus(
        storedStatus: String,
        helmDay: HelmDay,
        today: HelmDay,
        completedDays: Set<HelmDay>
    ) -> WeekAheadSessionStatus {
        if let plannedStatus = PlannedSessionStatus(rawValue: storedStatus) {
            switch plannedStatus {
            case .completed:
                return .completed
            case .shifted:
                return .shifted
            case .skipped:
                return .skipped
            case .pending:
                break
            }
        }

        if completedDays.contains(helmDay) {
            return .completed
        }
        if helmDay == today {
            return .today
        }
        if helmDay < today {
            return .missed
        }
        return .upcoming
    }

    private static func driftNote(
        for record: PlannedWorkoutRecord,
        helmDay: HelmDay,
        calendar: Calendar
    ) -> String? {
        guard let plannedStatus = PlannedSessionStatus(rawValue: record.status) else {
            return nil
        }
        switch plannedStatus {
        case .shifted:
            guard let originalDay = originalPlannedDay(from: record.id), originalDay != helmDay else {
                return nil
            }
            return "Was \(shortDayLabel(for: originalDay, calendar: calendar))"
        case .skipped, .completed, .pending:
            return nil
        }
    }

    private static func originalPlannedDay(from recordID: String) -> HelmDay? {
        let prefix = "planned-"
        guard recordID.hasPrefix(prefix) else { return nil }
        let suffix = String(recordID.dropFirst(prefix.count))
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

    private static func shortDayLabel(for helmDay: HelmDay, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE · MMM d"
        guard let date = calendar.date(from: helmDay.dateComponents()) else {
            return helmDay.formatted
        }
        return formatter.string(from: date)
    }

    private static func dayLabel(for helmDay: HelmDay, today: HelmDay, calendar: Calendar) -> String {
        if helmDay == today {
            return "Today"
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE · MMM d"
        guard let date = calendar.date(from: helmDay.dateComponents()) else {
            return "\(helmDay.month)/\(helmDay.day)"
        }
        return formatter.string(from: date)
    }
}
