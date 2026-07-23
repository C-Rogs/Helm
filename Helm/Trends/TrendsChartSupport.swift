import Core
import Foundation
import PlanKit

enum TrendsChartSupport {
    static func chartDate(for helmDay: HelmDay, calendar: Calendar = .current) -> Date {
        helmDay.startInstant(calendar: calendar)
            ?? calendar.date(from: helmDay.dateComponents())
            ?? .now
    }

    static func shortLabel(for helmDay: HelmDay) -> String {
        String(format: "%02d/%02d", helmDay.month, helmDay.day)
    }

    static func muscleLabel(_ muscle: MuscleGroup) -> String {
        switch muscle {
        case .chest: "Chest"
        case .back: "Back"
        case .shoulders: "Shoulders"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .quads: "Quads"
        case .hamstrings: "Hamstrings"
        case .glutes: "Glutes"
        case .calves: "Calves"
        case .abs: "Abs"
        }
    }
}
