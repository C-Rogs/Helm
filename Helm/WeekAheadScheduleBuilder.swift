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
        cutoff: DayCutoff = .default
    ) throws -> WeekAheadScheduleModel {
        let endDay = today.adding(days: horizonDays - 1, calendar: calendar)
        let records = try store.plan.fetchPlannedWorkouts(from: today, through: endDay)
        guard !records.isEmpty else {
            return WeekAheadScheduleModel(rows: [])
        }

        let history = try PrescriptionHistoryBuilder.history(
            from: store,
            endingAt: endDay,
            calendar: calendar,
            cutoff: cutoff
        )
        let completedDays = Set(history.sessions.map(\.helmDay))

        let rows = try records.compactMap { record -> WeekAheadScheduleRow? in
            let helmDay = try record.decodedHelmDay()
            let payload = PlannedWorkoutSessionDecoder.decode(from: record.sessionJSON)
            let splitLabel = payload?.splitLabel ?? "Session"
            let note = payload?.primaryNote
            let status = resolvedStatus(
                storedStatus: record.status,
                helmDay: helmDay,
                today: today,
                completedDays: completedDays
            )

            return WeekAheadScheduleRow(
                id: record.id,
                dayLabel: dayLabel(for: helmDay, today: today, calendar: calendar),
                splitLabel: splitLabel,
                note: note,
                status: status,
                isToday: helmDay == today
            )
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
            case .completed, .shifted:
                return .completed
            case .skipped:
                return .missed
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
