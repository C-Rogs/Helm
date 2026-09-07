import Core
import Foundation
import HealthKitIngest
import Persistence
import Testing

/// Companion to PersistenceTests.SleepHotPathBenchmarks: readiness history slice.
@Suite("Sleep hot-path benchmarks (readiness)")
struct SleepHotPathReadinessBenchmarks {
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

    @Test("decision matrix: readinessHistory30d")
    func readinessHistoryMatrix() throws {
        var results: [Row] = []
        let calendar = SleepBenchSeeder.londonCalendar

        for scale in SleepBenchSeeder.Scale.allCases {
            let store = try PersistenceStore.inMemory()
            let seeded = try SleepBenchSeeder.seed(store: store, scale: scale)
            let iterations = scale == .typical ? 4 : 2

            let totalMs = measure(iterations: iterations) {
                _ = try? ReadinessHistoryBuilder.history(
                    from: store,
                    from: seeded.startDay,
                    through: seeded.endDay,
                    calendar: calendar
                )
            }
            let perCallUs = (totalMs * 1000.0) / Double(max(iterations, 1))
            results.append(
                Row(
                    caseName: "readinessHistory30d",
                    scale: scale.rawValue,
                    rows: seeded.rows,
                    iterations: iterations,
                    totalMs: totalMs,
                    perOpUs: perCallUs,
                    relativeToIsoDecode: nil
                )
            )
        }

        let url = URL(fileURLWithPath: "/tmp/helm-sleep-hotpath.json")
        var existing: [Row] = []
        if let data = try? Data(contentsOf: url),
           let matrix = try? JSONDecoder().decode(Matrix.self, from: data) {
            existing = matrix.rows.filter { $0.caseName != "readinessHistory30d" }
        }
        let merged = Matrix(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            rows: existing + results
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(merged)
        try data.write(to: url, options: .atomic)

        print("HELM_SLEEP_HOTPATH_JSON=\(url.path)")
        print(String(data: data, encoding: .utf8) ?? "")
        #expect(results.count == 2)
    }

    private func measure(iterations: Int, body: () -> Void) -> Double {
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
}
