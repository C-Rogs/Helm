import Core
import Foundation
import PlanKit

public enum SessionSplitPlanner {
    private static let templates: [[MuscleGroup]] = [
        [.chest, .shoulders, .triceps],
        [.back, .biceps],
        [.quads, .hamstrings, .glutes]
    ]

    public static func targetMuscles(for day: HelmDay, emphasis: String?, calendar: Calendar = .current) -> [MuscleGroup] {
        let weekdayIndex = weekdayIndex(for: day, calendar: calendar)
        var muscles = templates[weekdayIndex % templates.count]

        guard let emphasis = emphasis?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !emphasis.isEmpty
        else {
            return muscles
        }

        if emphasis.contains("v-taper") || emphasis.contains("vtaper") {
            return [.shoulders, .back, .chest]
        }
        if emphasis.contains("leg") {
            return [.quads, .hamstrings, .glutes, .calves]
        }
        if emphasis.contains("arm") {
            return [.biceps, .triceps, .shoulders]
        }

        return muscles
    }

    static func remainingSessionsThisWeek(completedThisWeek: Int, plannedPerWeek: Int = 3) -> Int {
        max(1, plannedPerWeek - completedThisWeek)
    }

    private static func weekdayIndex(for day: HelmDay, calendar: Calendar) -> Int {
        let components = day.dateComponents()
        guard let date = calendar.date(from: components) else { return 0 }
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }
}
