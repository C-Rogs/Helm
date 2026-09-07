import Core
import Foundation
import Testing
@testable import Persistence

@Suite("ISO8601Coding")
struct ISO8601CodingTests {
    @Test("fast path matches Foundation formatter for Helm wire format")
    func fastPathMatchesFoundation() throws {
        let samples: [Date] = [
            Date(timeIntervalSince1970: 0),
            Date(timeIntervalSince1970: 1_721_548_921.123),
            Date(timeIntervalSince1970: 1_700_000_000.001),
            Date(timeIntervalSince1970: 1_893_456_789.999),
            Date()
        ]
        for original in samples {
            let encoded = ISO8601Coding.string(from: original)
            let fast = try #require(FastISO8601.date(from: encoded))
            let foundation = try ISO8601Coding.date(from: encoded)
            #expect(abs(fast.timeIntervalSince1970 - foundation.timeIntervalSince1970) < 0.001)
            #expect(abs(fast.timeIntervalSince1970 - original.timeIntervalSince1970) < 0.001)
        }
        // Offset form (legacy / imported rows).
        let offset = "2024-07-21T09:02:01.123+01:00"
        let offsetDate = try #require(FastISO8601.date(from: offset))
        #expect(abs(offsetDate.timeIntervalSince1970 - 1_721_548_921.123) < 0.001)
    }

    @Test("fast path rejects garbage so Foundation fallback can throw")
    func fastPathRejectsGarbage() {
        #expect(FastISO8601.date(from: "not-a-date") == nil)
        #expect(FastISO8601.date(from: "2024-13-01T00:00:00Z") == nil)
        #expect(throws: PersistenceError.self) {
            _ = try ISO8601Coding.date(from: "not-a-date")
        }
    }

    @Test("round-trips dates with fractional seconds")
    func roundTripFractionalSeconds() throws {
        let original = Date(timeIntervalSince1970: 1_721_548_921.123)
        let encoded = ISO8601Coding.string(from: original)
        let decoded = try ISO8601Coding.date(from: encoded)
        #expect(abs(decoded.timeIntervalSince1970 - original.timeIntervalSince1970) < 0.001)
        #expect(encoded.contains("."))
    }

    @Test("rejects invalid strings")
    func rejectsInvalid() {
        #expect(throws: PersistenceError.self) {
            _ = try ISO8601Coding.date(from: "not-a-date")
        }
    }

    @Test("concurrent encode/decode stays consistent")
    func concurrentAccess() async throws {
        let dates = (0..<200).map { Date(timeIntervalSince1970: 1_700_000_000 + Double($0) + 0.456) }
        let results = try await withThrowingTaskGroup(of: Bool.self) { group in
            for date in dates {
                group.addTask {
                    let encoded = ISO8601Coding.string(from: date)
                    let decoded = try ISO8601Coding.date(from: encoded)
                    return abs(decoded.timeIntervalSince1970 - date.timeIntervalSince1970) < 0.001
                }
            }
            var ok = true
            for try await result in group {
                ok = ok && result
            }
            return ok
        }
        #expect(results)
    }

    @Test("sleep overlapping fetch round-trips many ISO timestamps")
    func sleepOverlappingUsesCachedFormatter() throws {
        let store = try PersistenceStore.inMemory()
        let calendar = Calendar(identifier: .gregorian)
        let day = HelmDay(year: 2026, month: 7, day: 22)
        var records: [SleepRecord] = []
        for hour in 0..<40 {
            let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 22, minute: hour % 60, second: hour))!
            let end = start.addingTimeInterval(60)
            records.append(
                SleepRecord(
                    start: start,
                    end: end,
                    helmDay: day,
                    stage: .asleepCore,
                    sourceBundleID: "com.apple.Health"
                )
            )
        }
        try store.sleep.replaceAll(for: day, records: records)

        let windowStart = calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 20))!
        let windowEnd = calendar.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 12))!
        let fetched = try store.sleep.fetchOverlapping(start: windowStart, end: windowEnd)
        #expect(fetched.count == 40)
        #expect(fetched.map(\.start) == records.map(\.start))
    }
}
