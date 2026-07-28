import Foundation

public extension WeekAheadScheduleModel {
    static let weekAheadFixture = WeekAheadScheduleModel(rows: [
        WeekAheadScheduleRow(
            id: "planned-2026-07-28",
            dayLabel: "Today",
            splitLabel: "Pull",
            note: "Push already logged this week - Pull is next.",
            status: .today,
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
            isToday: false
        ),
        WeekAheadScheduleRow(
            id: "planned-2026-07-27",
            dayLabel: "Mon · Jul 27",
            splitLabel: "Push",
            status: .completed,
            isToday: false
        ),
        WeekAheadScheduleRow(
            id: "planned-2026-07-26",
            dayLabel: "Sun · Jul 26",
            splitLabel: "Legs",
            status: .missed,
            isToday: false
        )
    ])
}
