import Foundation

public extension WeekAheadScheduleModel {
    static let busyDayFixture = WeekAheadScheduleModel(rows: [
        WeekAheadScheduleRow(
            id: "planned-2026-07-28",
            dayLabel: "Today",
            splitLabel: "Pull",
            note: "Push already logged this week - Pull is next.",
            status: .today,
            busyDayHint: "Busy · 5h scheduled",
            isToday: true
        ),
        WeekAheadScheduleRow(
            id: "planned-2026-07-29",
            dayLabel: "Wed · Jul 29",
            splitLabel: "Legs",
            status: .upcoming,
            isToday: false
        ),
        WeekAheadScheduleRow(
            id: "planned-2026-07-30",
            dayLabel: "Thu · Jul 30",
            splitLabel: "Push",
            status: .upcoming,
            busyDayHint: "Busy · 3 events",
            isToday: false
        )
    ])
}
