import Core
import Foundation

enum ISO8601Coding {
    private final class FormatterBox: @unchecked Sendable {
        let lock = NSLock()
        let formatter: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()
    }

    private static let box = FormatterBox()

    static func string(from date: Date) -> String {
        box.lock.lock()
        defer { box.lock.unlock() }
        return box.formatter.string(from: date)
    }

    static func date(from string: String) throws -> Date {
        if let fast = FastISO8601.date(from: string) {
            return fast
        }
        return try dateUsingFoundationFormatter(from: string)
    }

    /// Foundation-only decode for benches / fallback comparison.
    static func dateUsingFoundationFormatter(from string: String) throws -> Date {
        box.lock.lock()
        defer { box.lock.unlock() }
        guard let date = box.formatter.date(from: string) else {
            throw PersistenceError.migrationFailed("invalid ISO8601 date: \(string)")
        }
        return date
    }
}

/// Unlock-free parser for the subset Helm writes via `ISO8601DateFormatter`
/// (`.withInternetDateTime` + `.withFractionalSeconds`): `yyyy-MM-dd'T'HH:mm:ss(.SSS)Z` / `±HH:MM`.
enum FastISO8601 {
    static func date(from string: String) -> Date? {
        let utf8 = Array(string.utf8)
        let count = utf8.count
        guard count >= 20 else { return nil }

        func digits(_ i: Int, _ n: Int) -> Int? {
            guard i + n <= count else { return nil }
            var value = 0
            for offset in 0..<n {
                let b = utf8[i + offset]
                guard b >= 48, b <= 57 else { return nil }
                value = value * 10 + Int(b - 48)
            }
            return value
        }

        guard
            let year = digits(0, 4),
            utf8[4] == UInt8(ascii: "-"),
            let month = digits(5, 2), month >= 1, month <= 12,
            utf8[7] == UInt8(ascii: "-"),
            let day = digits(8, 2), day >= 1, day <= 31,
            utf8[10] == UInt8(ascii: "T") || utf8[10] == UInt8(ascii: "t"),
            let hour = digits(11, 2), hour <= 23,
            utf8[13] == UInt8(ascii: ":"),
            let minute = digits(14, 2), minute <= 59,
            utf8[16] == UInt8(ascii: ":"),
            let second = digits(17, 2), second <= 60
        else { return nil }

        var index = 19
        var fraction = 0.0
        if index < count, utf8[index] == UInt8(ascii: ".") {
            index += 1
            var scale = 0.1
            var sawDigit = false
            while index < count, utf8[index] >= 48, utf8[index] <= 57 {
                sawDigit = true
                fraction += Double(utf8[index] - 48) * scale
                scale *= 0.1
                index += 1
            }
            guard sawDigit else { return nil }
        }

        var secondsFromGMT = 0
        guard index < count else { return nil }
        let tz = utf8[index]
        if tz == UInt8(ascii: "Z") || tz == UInt8(ascii: "z") {
            index += 1
        } else if tz == UInt8(ascii: "+") || tz == UInt8(ascii: "-") {
            guard
                let th = digits(index + 1, 2), th <= 23,
                index + 3 < count, utf8[index + 3] == UInt8(ascii: ":"),
                let tm = digits(index + 4, 2), tm <= 59
            else { return nil }
            let sign = tz == UInt8(ascii: "-") ? -1 : 1
            secondsFromGMT = sign * (th * 3600 + tm * 60)
            index += 6
        } else {
            return nil
        }
        guard index == count else { return nil }

        let days = daysFromCivil(year: year, month: month, day: day)
        let seconds =
            Double(days * 86_400 + hour * 3_600 + minute * 60 + second - secondsFromGMT) + fraction
        return Date(timeIntervalSince1970: seconds)
    }

    /// Civil date to days since 1970-01-01 (Howard Hinnant).
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        var y = year
        var m = month
        y -= m <= 2 ? 1 : 0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
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
