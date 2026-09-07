import Core
import Foundation
import Testing
@testable import Persistence

/// Decision harness for sleep ISO decode vs numeric timestamps vs full history cost.
/// Always passes unless a case throws. Writes `/tmp/helm-sleep-hotpath.json`.
@Suite("Sleep hot-path benchmarks")
struct SleepHotPathBenchmarks {
    private struct Row: Codable {
        var caseName: String
        var scale: String
        var rows: Int
        var iterations: Int
        var totalMs: Double
        var perOpUs: Double
        var relativeToIsoDecode: Double?
    }

    private struct Matrix: Codable {
        var generatedAt: String
        var rows: [Row]
    }

    @Test("decision matrix: ISO vs epoch vs fastISO vs fetch slices")
    func decisionMatrix() throws {
        var results: [Row] = []

        for scale in SleepBenchSeeder.Scale.allCases {
            let store = try PersistenceStore.inMemory()
            let seeded = try SleepBenchSeeder.seed(store: store, scale: scale)
            let calendar = SleepBenchSeeder.londonCalendar
            let windowStart = SleepAggregation.sleepWindowStart(
                for: calendar.date(from: seeded.startDay.dateComponents())!,
                calendar: calendar
            )
            let windowEnd = SleepAggregation.sleepWindowEnd(
                for: calendar.date(from: seeded.endDay.dateComponents())!,
                calendar: calendar
            )

            let sampleDates = try store.sleep.fetchOverlapping(start: windowStart, end: windowEnd)
            let isoStrings = sampleDates.map { ISO8601Coding.string(from: $0.start) }
            let epochs = sampleDates.map(\.start.timeIntervalSince1970)
            #expect(!isoStrings.isEmpty)

            let decodeIterations = scale == .typical ? 8 : 4
            let pathIterations = scale == .typical ? 6 : 3

            let foundation = measure(iterations: decodeIterations) {
                for s in isoStrings {
                    _ = try? ISO8601Coding.dateUsingFoundationFormatter(from: s)
                }
            }
            results.append(
                makeRow(
                    caseName: "foundationISODecodeOnly",
                    scale: scale,
                    rows: isoStrings.count,
                    iterations: decodeIterations,
                    totalMs: foundation,
                    baselineUs: nil
                )
            )
            let foundationPerOpUs =
                (foundation * 1000.0) / Double(decodeIterations * isoStrings.count)

            let iso = measure(iterations: decodeIterations) {
                for s in isoStrings {
                    _ = try? ISO8601Coding.date(from: s)
                }
            }
            results.append(
                makeRow(
                    caseName: "isoDecodeOnly",
                    scale: scale,
                    rows: isoStrings.count,
                    iterations: decodeIterations,
                    totalMs: iso,
                    baselineUs: foundationPerOpUs
                )
            )

            let epoch = measure(iterations: decodeIterations) {
                for e in epochs {
                    _ = Date(timeIntervalSince1970: e)
                }
            }
            results.append(
                makeRow(
                    caseName: "epochDecodeOnly",
                    scale: scale,
                    rows: epochs.count,
                    iterations: decodeIterations,
                    totalMs: epoch,
                    baselineUs: foundationPerOpUs
                )
            )

            let fast = measure(iterations: decodeIterations) {
                for s in isoStrings {
                    _ = FastISO8601.date(from: s)
                }
            }
            results.append(
                makeRow(
                    caseName: "fastISODecodeOnly",
                    scale: scale,
                    rows: isoStrings.count,
                    iterations: decodeIterations,
                    totalMs: fast,
                    baselineUs: foundationPerOpUs
                )
            )

            let fetch = measure(iterations: pathIterations) {
                _ = try? store.sleep.fetchOverlapping(start: windowStart, end: windowEnd)
            }
            results.append(
                makeRow(
                    caseName: "fetchOverlapping",
                    scale: scale,
                    rows: seeded.rows,
                    iterations: pathIterations,
                    totalMs: fetch,
                    baselineUs: foundationPerOpUs
                )
            )

            let raw = measure(iterations: pathIterations) {
                _ = try? store.sleep.fetchOverlappingISOStrings(start: windowStart, end: windowEnd)
            }
            results.append(
                makeRow(
                    caseName: "fetchRowsNoDecode",
                    scale: scale,
                    rows: seeded.rows,
                    iterations: pathIterations,
                    totalMs: raw,
                    baselineUs: foundationPerOpUs
                )
            )

            let wake = calendar.date(from: seeded.endDay.dateComponents())!
            let night = measure(iterations: pathIterations) {
                _ = try? store.sleep.nightSummary(forWakeCalendarDay: wake, calendar: calendar)
            }
            results.append(
                makeRow(
                    caseName: "nightSummaryOne",
                    scale: scale,
                    rows: seeded.rows,
                    iterations: pathIterations,
                    totalMs: night,
                    baselineUs: foundationPerOpUs
                )
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let matrix = Matrix(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            rows: results
        )
        let data = try encoder.encode(matrix)
        let url = URL(fileURLWithPath: "/tmp/helm-sleep-hotpath.json")
        try data.write(to: url, options: .atomic)

        print("HELM_SLEEP_HOTPATH_JSON=\(url.path)")
        print(String(data: data, encoding: .utf8) ?? "")

        #expect(results.count >= 14)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    private func measure(iterations: Int, body: () -> Void) -> Double {
        // Warm-up
        body()
        let clock = ContinuousClock()
        let start = clock.now
        for _ in 0..<iterations {
            body()
        }
        let elapsed = start.duration(to: clock.now)
        return Double(elapsed.components.seconds) * 1000.0
            + Double(elapsed.components.attoseconds) / 1e15 * 1000.0
    }

    private func makeRow(
        caseName: String,
        scale: SleepBenchSeeder.Scale,
        rows: Int,
        iterations: Int,
        totalMs: Double,
        baselineUs: Double?
    ) -> Row {
        let ops = max(iterations * max(rows, 1), 1)
        let perOpUs = (totalMs * 1000.0) / Double(ops)
        let relative = baselineUs.map { perOpUs / max($0, 0.000_001) }
        return Row(
            caseName: caseName,
            scale: scale.rawValue,
            rows: rows,
            iterations: iterations,
            totalMs: totalMs,
            perOpUs: perOpUs,
            relativeToIsoDecode: relative
        )
    }
}
