import Foundation

public struct WorkoutHistoryMonthSection: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let sessions: [WorkoutSessionSummary]

    public init(id: String, title: String, sessions: [WorkoutSessionSummary]) {
        self.id = id
        self.title = title
        self.sessions = sessions
    }
}

public enum WorkoutHistoryFormatting {
    public static func durationMinutes(startedAt: Date, endedAt: Date?) -> Int? {
        guard let endedAt else { return nil }
        let seconds = endedAt.timeIntervalSince(startedAt)
        guard seconds > 0 else { return nil }
        return max(1, Int((seconds / 60).rounded()))
    }

    public static func durationLabel(startedAt: Date, endedAt: Date?) -> String? {
        guard let minutes = durationMinutes(startedAt: startedAt, endedAt: endedAt) else {
            return nil
        }
        if minutes >= 60 {
            let hours = minutes / 60
            let remainder = minutes % 60
            if remainder == 0 {
                return "\(hours)h"
            }
            return "\(hours)h \(remainder)m"
        }
        return "\(minutes) min"
    }

    public static func contextualDateTimeLabel(
        _ date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let time = shortTimeFormatter(calendar: calendar).string(from: date)
        if calendar.isDate(date, inSameDayAs: now) {
            return "Today · \(time)"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday · \(time)"
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            let day = monthDayFormatter(calendar: calendar).string(from: date)
            return "\(day) · \(time)"
        }
        let day = monthDayYearFormatter(calendar: calendar).string(from: date)
        return "\(day) · \(time)"
    }

    public static func monthSectionTitle(
        _ date: Date,
        calendar: Calendar = .current
    ) -> String {
        monthYearFormatter(calendar: calendar).string(from: date)
    }

    public static func monthSectionID(
        _ date: Date,
        calendar: Calendar = .current
    ) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        return "\(year)-\(month)"
    }

    public static func groupByMonth(
        _ sessions: [WorkoutSessionSummary],
        calendar: Calendar = .current
    ) -> [WorkoutHistoryMonthSection] {
        var sections: [WorkoutHistoryMonthSection] = []
        var currentID: String?
        var currentTitle: String?
        var currentSessions: [WorkoutSessionSummary] = []

        for session in sessions {
            let sectionID = monthSectionID(session.startedAt, calendar: calendar)
            let sectionTitle = monthSectionTitle(session.startedAt, calendar: calendar)
            if currentID == sectionID {
                currentSessions.append(session)
            } else {
                if let currentID, let currentTitle, !currentSessions.isEmpty {
                    sections.append(
                        WorkoutHistoryMonthSection(
                            id: currentID,
                            title: currentTitle,
                            sessions: currentSessions
                        )
                    )
                }
                currentID = sectionID
                currentTitle = sectionTitle
                currentSessions = [session]
            }
        }

        if let currentID, let currentTitle, !currentSessions.isEmpty {
            sections.append(
                WorkoutHistoryMonthSection(
                    id: currentID,
                    title: currentTitle,
                    sessions: currentSessions
                )
            )
        }

        return sections
    }

    public static func volumeLabel(kilograms: Double) -> String {
        if kilograms >= 1000 {
            return String(format: "%.1fk", kilograms / 1000)
        }
        if kilograms.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", kilograms)
        }
        return String(format: "%.0f", kilograms.rounded())
    }

    public static func kcalLabel(kilocalories: Double) -> String {
        if kilocalories >= 1000 {
            return String(format: "%.0fk", kilocalories / 1000)
        }
        return String(format: "%.0f", kilocalories)
    }

    public static func distanceLabel(meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }

    public static func accessibilityLabel(for summary: WorkoutSessionSummary) -> String {
        var parts: [String] = [summary.title ?? "Workout"]
        parts.append(contextualDateTimeLabel(summary.startedAt))
        if let duration = durationLabel(startedAt: summary.startedAt, endedAt: summary.endedAt) {
            parts.append(duration)
        }

        if summary.source == .healthKit {
            if let kcal = summary.hkActiveEnergyKilocalories {
                parts.append("\(kcalLabel(kilocalories: kcal)) kilocalories")
            }
            if let distance = summary.hkTotalDistanceMeters {
                parts.append(distanceLabel(meters: distance))
            }
        } else {
            parts.append("\(summary.exerciseCount) exercises")
            parts.append("\(summary.totalSetCount) sets")
            parts.append("\(volumeLabel(kilograms: summary.totalVolumeKilograms)) kilograms volume")
        }
        return parts.joined(separator: ", ")
    }

    private static func shortTimeFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale.current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    private static func monthDayFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }

    private static func monthDayYearFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("MMMdyyyy")
        return formatter
    }

    private static func monthYearFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter
    }
}
