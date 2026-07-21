import Foundation
import Testing
@testable import Diagnostics

@Suite("DiagnosticsLog ring buffer")
struct DiagnosticsLogTests {
    @Test("ring buffer evicts oldest entries at capacity")
    func ringBufferCapacity() async {
        let log = DiagnosticsLog()

        for index in 0..<600 {
            await log.record(
                category: .ui,
                level: .info,
                message: "entry \(index)"
            )
        }

        let entries = await log.entriesOldestFirst()
        #expect(entries.count == DiagnosticsLog.capacity)
        #expect(entries.first?.message == "entry 100")
        #expect(entries.last?.message == "entry 599")
    }

    @Test("silent error capture records type and stack trace")
    func captureError() async {
        let log = DiagnosticsLog()
        struct SampleFailure: Error {}

        await log.capture(
            error: SampleFailure(),
            category: .ui,
            message: "sample capture",
            context: ["source": "test"]
        )

        let entry = await log.entriesNewestFirst().first
        #expect(entry?.level == .error)
        #expect(entry?.message == "sample capture")
        #expect(entry?.errorType?.contains("SampleFailure") == true)
        #expect(entry?.stackTrace?.isEmpty == false)
        #expect(entry?.context?["source"] == "test")
    }

    @Test("concurrent writes remain thread-safe")
    func concurrentWrites() async {
        let log = DiagnosticsLog()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<200 {
                group.addTask {
                    await log.record(
                        category: .ui,
                        level: .debug,
                        message: "concurrent \(index)"
                    )
                }
            }
        }

        #expect(await log.count() == 200)
    }

    @Test("silent failure helper does not rethrow")
    func silentFailureHelper() async {
        let log = DiagnosticsLog()
        struct Boom: Error {}

        let value = await SilentFailure.run(log: log, category: .ui, context: ["test": "true"]) {
            throw Boom()
        }

        #expect(value == nil)
        #expect(await log.count() == 1)
    }
}

@Suite("LogExportService")
struct LogExportServiceTests {
    @Test("export bundle contains documented files")
    func exportSchema() async throws {
        let log = DiagnosticsLog()
        await log.record(
            category: .ui,
            level: .info,
            message: "export test",
            context: ["ticket": "M0.3"]
        )

        let service = LogExportService(log: log)
        let environment = ExportEnvironment(
            appVersion: "1.0.0",
            buildNumber: "42",
            schemaVersion: 0,
            exerciseSeedVersion: 0,
            deviceModel: "TestDevice",
            osVersion: "26.0"
        )

        let zipURL = try await service.exportBundle(environment: environment)
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let archive = try Data(contentsOf: zipURL)
        func contains(_ string: String) -> Bool {
            archive.range(of: Data(string.utf8)) != nil
        }
        #expect(contains("manifest.json"))
        #expect(contains("ring_buffer.json"))
        #expect(contains("oslog_extract.txt"))
        #expect(contains("export test"))
        #expect(contains("TestDevice"))
    }
}
