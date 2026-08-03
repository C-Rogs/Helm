import Core
import Foundation
import Persistence

struct SleepAnalysisNight: Identifiable, Sendable {
    let wakeDay: Date
    let summary: SleepNightSummary

    var id: Date { wakeDay }
}

struct SleepAnalysisModel: Sendable {
    let tonight: SleepNightSummary
    let recentNights: [SleepAnalysisNight]
}

enum SleepAnalysisBuilder {
    static let recentNightCount = 14
    /// Cap calendar lookback when filling `recentNightCount` nights with data.
    static let maxLookbackDays = 60

    static func load(
        store: PersistenceStore,
        wakeDay: Date = Calendar.current.startOfDay(for: Date()),
        calendar: Calendar = .current
    ) throws -> SleepAnalysisModel {
        let tonight = try store.sleep.nightSummary(forWakeCalendarDay: wakeDay, calendar: calendar)

        var recent: [SleepAnalysisNight] = []
        if tonight.asleepHours != nil {
            recent.append(SleepAnalysisNight(wakeDay: wakeDay, summary: tonight))
        }

        var offset = 1
        while recent.count < recentNightCount, offset <= maxLookbackDays {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: wakeDay) else { break }
            let summary = try store.sleep.nightSummary(forWakeCalendarDay: day, calendar: calendar)
            if summary.asleepHours != nil {
                recent.append(SleepAnalysisNight(wakeDay: day, summary: summary))
            }
            offset += 1
        }

        return SleepAnalysisModel(tonight: tonight, recentNights: recent)
    }
}
