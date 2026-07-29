import Foundation

/// Formats sleep durations for display (hours + minutes, not decimal hours).
public enum SleepDurationFormatting {
    public static func hoursAndMinutes(from hours: Double) -> String {
        let totalMinutes = max(0, Int((hours * 60).rounded()))
        let hourComponent = totalMinutes / 60
        let minuteComponent = totalMinutes % 60
        if hourComponent == 0 {
            return "\(minuteComponent)m"
        }
        if minuteComponent == 0 {
            return "\(hourComponent)h"
        }
        return "\(hourComponent)h \(minuteComponent)m"
    }

    public static func hoursAndMinutesLabel(from hours: Double) -> String {
        "\(hoursAndMinutes(from: hours))"
    }
}
