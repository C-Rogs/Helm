import Foundation
import GRDB

public actor PersistenceStore {
    public nonisolated let dailyMetrics: DailyMetricsRepository
    public nonisolated let bodyComposition: BodyCompositionRepository
    public nonisolated let sleep: SleepRepository
    public nonisolated let nutrition: NutritionRepository

    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
        dailyMetrics = DailyMetricsRepository(pool: pool)
        bodyComposition = BodyCompositionRepository(pool: pool)
        sleep = SleepRepository(pool: pool)
        nutrition = NutritionRepository(pool: pool)
    }

    public static func open(at url: URL) throws -> PersistenceStore {
        let pool = try DatabaseFactory.makePool(at: url)
        try AppMigrator().migrate(pool)
        return PersistenceStore(pool: pool)
    }

    public static func inMemory() throws -> PersistenceStore {
        let pool = try DatabaseFactory.makeInMemoryPool()
        try AppMigrator().migrate(pool)
        return PersistenceStore(pool: pool)
    }

    public var schemaVersion: Int {
        SchemaVersion.latest
    }

    public func checkpoint() throws {
        _ = try pool.writeWithoutTransaction { db in
            try db.checkpoint(.passive)
        }
    }
}
