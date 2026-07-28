import Foundation

public extension WeekAheadScheduleModel {
    /// Mirrors PlanKit drift-policy scenarios for UI snapshot coverage.
    static let driftScenarioFixture = WeekAheadScheduleModel(rows: [
        WeekAheadScheduleRow(
            id: "planned-2026-07-20",
            dayLabel: "Tue · Jul 22",
            splitLabel: "Pull",
            note: "Logged two days late - session shifted.",
            status: .shifted,
            driftNote: "Was Sun · Jul 20",
            isToday: false
        ),
        WeekAheadScheduleRow(
            id: "planned-2026-07-20",
            dayLabel: "Mon · Jul 20",
            splitLabel: "Push",
            status: .skipped,
            isToday: false
        ),
        WeekAheadScheduleRow(
            id: "planned-2026-07-22",
            dayLabel: "Wed · Jul 22",
            splitLabel: "Legs",
            status: .skipped,
            isToday: false
        ),
        WeekAheadScheduleRow(
            id: "planned-2026-07-24",
            dayLabel: "Fri · Jul 24",
            splitLabel: "Upper",
            status: .completed,
            isToday: false
        ),
        WeekAheadScheduleRow(
            id: "planned-2026-07-25",
            dayLabel: "Sat · Jul 25",
            splitLabel: "Lower",
            status: .upcoming,
            isToday: false
        )
    ])
}
