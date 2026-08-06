import Foundation

public extension WeekAheadScheduleModel {
    static let busyDayFixture = WeekAheadScheduleModel(rows: [
        WeekAheadScheduleRow(
            id: "2026-07-28",
            dayLabel: "Today",
            splitLabel: "Rest",
            status: .rest,
            busyDayHint: "Busy · 5h scheduled",
            isToday: true
        ),
        WeekAheadScheduleRow(
            id: "2026-07-29",
            dayLabel: "Wed · Jul 29",
            splitLabel: "Pull",
            note: "Moved off busy day.",
            status: .upcoming,
            isToday: false
        ),
        WeekAheadScheduleRow(
            id: "2026-07-30",
            dayLabel: "Thu · Jul 30",
            splitLabel: "Rest",
            status: .rest,
            isToday: false
        ),
        WeekAheadScheduleRow(
            id: "2026-07-31",
            dayLabel: "Fri · Jul 31",
            splitLabel: "Legs",
            status: .upcoming,
            isToday: false
        ),
        WeekAheadScheduleRow(
            id: "2026-08-01",
            dayLabel: "Sat · Aug 1",
            splitLabel: "Rest",
            status: .rest,
            busyDayHint: "Busy · 3 events",
            isToday: false
        ),
        WeekAheadScheduleRow(
            id: "2026-08-02",
            dayLabel: "Sun · Aug 2",
            splitLabel: "Push",
            status: .upcoming,
            isToday: false
        ),
        WeekAheadScheduleRow(
            id: "2026-08-03",
            dayLabel: "Mon · Aug 3",
            splitLabel: "Rest",
            status: .rest,
            isToday: false
        )
    ])
}
