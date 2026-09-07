import Core
import Foundation
import Persistence

/// Mirror of PersistenceTests.SleepBenchSeeder so HealthKitIngestTests can seed identical N.
enum SleepBenchSeeder {
    enum Scale: String, CaseIterable {
        case typical
        case heavy

        var intervalsPerNight: Int {
            switch self {
            case .typical: 40
            case .heavy: 80
            }
        }

        var nightCount: Int {
            switch self {
            case .typical: 30
            case .heavy: 60
            }
        }

        var expectedRows: Int { intervalsPerNight * nightCount }
    }

    static let londonCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    static func seed(
        store: PersistenceStore,
        scale: Scale,
        endingAt endDay: HelmDay = HelmDay(year: 2026, month: 7, day: 31),
        calendar: Calendar = londonCalendar
    ) throws -> (rows: Int, startDay: HelmDay, endDay: HelmDay) {
        let startDay = endDay.adding(days: -(scale.nightCount - 1), calendar: calendar)
        var rows = 0
        for offset in 0..<scale.nightCount {
            let helmDay = startDay.adding(days: offset, calendar: calendar)
            guard let wakeDay = calendar.date(from: helmDay.dateComponents()) else { continue }
            let nightStart = calendar.date(byAdding: .hour, value: -6, to: wakeDay)
                ?? wakeDay.addingTimeInterval(-6 * 3600)
            var records: [SleepRecord] = []
            records.reserveCapacity(scale.intervalsPerNight)
            for i in 0..<scale.intervalsPerNight {
                let start = nightStart.addingTimeInterval(TimeInterval(i * 10 * 60) + TimeInterval(i % 7) * 0.123)
                let end = start.addingTimeInterval(8 * 60 + TimeInterval(i % 5))
                let stage: SleepAnalysisStage
                switch i % 5 {
                case 0: stage = .inBed
                case 1: stage = .asleepCore
                case 2: stage = .asleepDeep
                case 3: stage = .asleepREM
                default: stage = .awake
                }
                records.append(
                    SleepRecord(
                        start: start,
                        end: end,
                        helmDay: helmDay,
                        stage: stage,
                        sourceBundleID: "com.apple.Health"
                    )
                )
            }
            try store.sleep.replaceAll(for: helmDay, records: records)
            rows += records.count
        }
        return (rows, startDay, endDay)
    }
}
