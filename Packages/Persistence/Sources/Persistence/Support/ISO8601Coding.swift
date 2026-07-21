import Core
import Foundation

enum ISO8601Coding {
    static func string(from date: Date) -> String {
        let formatter = makeFormatter()
        return formatter.string(from: date)
    }

    static func date(from string: String) throws -> Date {
        let formatter = makeFormatter()
        guard let date = formatter.date(from: string) else {
            throw PersistenceError.migrationFailed("invalid ISO8601 date: \(string)")
        }
        return date
    }

    private static func makeFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

enum HelmDayColumn {
    static func encode(_ helmDay: HelmDay) -> String {
        helmDay.formatted
    }

    static func decode(_ value: String) throws -> HelmDay {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard
            parts.count == 3,
            let year = Int(parts[0]),
            let month = Int(parts[1]),
            let day = Int(parts[2])
        else {
            throw PersistenceError.migrationFailed("invalid helm day column: \(value)")
        }
        return HelmDay(year: year, month: month, day: day)
    }
}
