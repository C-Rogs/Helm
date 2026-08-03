import Core
import Foundation
import GRDB
import Testing
@testable import Persistence

@Suite("Database export")
struct DatabaseExportTests {
    private let day = HelmDay(year: 2026, month: 7, day: 21)

    @Test("checkpointed export produces openable SQLite with data")
    func exportProducesValidSQLite() async throws {
        let store = try PersistenceStore.inMemory()
        let metrics = DailyMetrics(
            helmDay: day,
            hrvSDNN: DurationMs(milliseconds: 55),
            restingHeartRate: 50,
            respiratoryRate: nil,
            wristTemperatureDeltaCelsius: nil,
            activeEnergy: nil,
            dietaryEnergy: nil,
            dietaryProteinGrams: nil,
            dietaryCarbohydrateGrams: nil,
            dietaryFatGrams: nil,
            priorDayTRIMP: nil
        )
        try store.dailyMetrics.upsert(metrics)

        let exportURL = try await store.exportCheckpointedCopy()
        defer { try? FileManager.default.removeItem(at: exportURL) }

        let exportedPool = try DatabaseFactory.makePool(at: exportURL)
        try AppMigrator().migrate(exportedPool)

        let rowCount = try await exportedPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM daily_metrics") ?? 0
        }
        #expect(rowCount == 1)

        let hrv = try await exportedPool.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT hrv_sdnn_ms FROM daily_metrics WHERE helm_day = ?",
                arguments: [day.formatted]
            )
        }
        #expect(hrv == 55)
    }

    @Test("default database location is excluded from iCloud backup")
    func iCloudBackupExcluded() throws {
        let url = try DatabaseLocation.defaultDatabaseURL()
        let directoryURL = url.deletingLastPathComponent()
        let values = try directoryURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test("included backup policy still opt-in")
    func iCloudBackupIncludedOptIn() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("helm-backup-policy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        try DatabaseLocation.applyBackupPolicy(.included, to: temp)
        let values = try temp.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == false)
    }
}
