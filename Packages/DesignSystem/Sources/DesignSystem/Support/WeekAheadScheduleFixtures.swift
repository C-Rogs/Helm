import Foundation

public extension WeekAheadScheduleModel {
    static let weekAheadFixture = WeekAheadScheduleModel(rows: [
        WeekAheadScheduleRow(
            id: "2026-07-28",
            dayLabel: "Today",
            splitLabel: "Pull",
            note: "Push already logged this week - Pull is next.",
            status: .today,
            isToday: true
        ),
        WeekAheadScheduleRow(
            id: "2026-07-29",
            dayLabel: "Wed · Jul 29",
            splitLabel: "Rest",
            status: .rest,
            isToday: false
        ),
        WeekAheadScheduleRow(
            id: "2026-07-30",
            dayLabel: "Thu · Jul 30",
            splitLabel: "Legs",
            status: .upcoming,
            isToday: false
        ),
        WeekAheadScheduleRow(
            id: "2026-07-31",
            dayLabel: "Fri · Jul 31",
            splitLabel: "Rest",
            status: .rest,
            isToday: false
        ),
        WeekAheadScheduleRow(
            id: "2026-08-01",
            dayLabel: "Sat · Aug 1",
            splitLabel: "Push",
            status: .upcoming,
            isToday: false
        ),
        WeekAheadScheduleRow(
            id: "2026-08-02",
            dayLabel: "Sun · Aug 2",
            splitLabel: "Rest",
            status: .rest,
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
