import Core
import Foundation
import GRDB

public struct ReadinessRepository: Sendable {
    private let pool: DatabasePool

    init(pool: DatabasePool) {
        self.pool = pool
    }

    public func upsertScore(helmDay: HelmDay, scoreJSON: String, computedAt: Date = Date()) throws {
        try pool.write { db in
            try ReadinessScoreRecord(helmDay: helmDay, scoreJSON: scoreJSON, computedAt: computedAt)
                .save(db)
        }
    }

    public func fetchScoreJSON(helmDay: HelmDay) throws -> String? {
        try pool.read { db in
            try ReadinessScoreRecord
                .fetchOne(db, key: HelmDayColumn.encode(helmDay))?
                .scoreJSON
        }
    }

    public func fetchScoreRange(from start: HelmDay, through end: HelmDay) throws -> [(HelmDay, String)] {
        try pool.read { db in
            let records = try ReadinessScoreRecord
                .filter(Column("helm_day") >= HelmDayColumn.encode(start))
                .filter(Column("helm_day") <= HelmDayColumn.encode(end))
                .order(Column("helm_day"))
                .fetchAll(db)
            return try records.map { record in
                (try record.decodedHelmDay(), record.scoreJSON)
            }
        }
    }

    /// Paginated readiness scores, newest first.
    public func fetchScores(endingAt end: HelmDay, limit: Int, offset: Int = 0) throws -> [(HelmDay, String)] {
        try pool.read { db in
            let records = try ReadinessScoreRecord
                .filter(Column("helm_day") <= HelmDayColumn.encode(end))
                .order(Column("helm_day").desc)
                .limit(limit, offset: offset)
                .fetchAll(db)
            return try records.map { record in
                (try record.decodedHelmDay(), record.scoreJSON)
            }
        }
    }

    public func upsertBaseline(stateJSON: String, updatedAt: Date = Date()) throws {
        try pool.write { db in
            try ReadinessBaselineRecord(stateJSON: stateJSON, updatedAt: updatedAt).save(db)
        }
    }

    public func fetchBaselineJSON() throws -> String? {
        try pool.read { db in
            try ReadinessBaselineRecord.fetchOne(db, key: ReadinessBaselineRecord.singletonID)?
                .stateJSON
        }
    }
}
