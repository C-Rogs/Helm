import Foundation
import GRDB

/// Persists coach advice records for follow-through tracking.
public final class CoachAdviceRecordStore: Sendable {
    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    public func insert(_ record: CoachAdviceRecord) throws {
        var record = record
        try pool.write { db in
            try record.insert(db)
        }
    }

    public func fetchByMessageID(_ messageID: String) throws -> CoachAdviceRecord? {
        try pool.read { db in
            try CoachAdviceRecord
                .filter(CoachAdviceRecord.Columns.messageID == messageID)
                .fetchOne(db)
        }
    }

    /// Fetch all advice records for a given helm day, optionally filtered by type and state.
    public func fetch(
        helmDay: String,
        adviceType: CoachAdviceRecord.AdviceType? = nil,
        state: CoachAdviceRecord.AdviceState? = nil
    ) throws -> [CoachAdviceRecord] {
        try pool.read { db in
            var query = CoachAdviceRecord
                .filter(CoachAdviceRecord.Columns.helmDay == helmDay)
            if let adviceType {
                query = query.filter(CoachAdviceRecord.Columns.adviceType == adviceType.rawValue)
            }
            if let state {
                query = query.filter(CoachAdviceRecord.Columns.state == state.rawValue)
            }
            return try query.fetchAll(db)
        }
    }

    public func updateState(
        messageID: String,
        state: CoachAdviceRecord.AdviceState,
        linkedSessionID: String? = nil
    ) throws {
        try pool.write { db in
            if var record = try CoachAdviceRecord
                .filter(CoachAdviceRecord.Columns.messageID == messageID)
                .fetchOne(db) {
                record.state = state
                if let sessionID = linkedSessionID {
                    record.linkedSessionID = sessionID
                }
                try record.update(db)
            }
        }
    }

    /// Supersede all pending advice of a given type (only newest matters).
    public func supersedePending(type: CoachAdviceRecord.AdviceType, excluding messageID: String) throws {
        try pool.write { db in
            try CoachAdviceRecord
                .filter(CoachAdviceRecord.Columns.adviceType == type.rawValue)
                .filter(CoachAdviceRecord.Columns.state == CoachAdviceRecord.AdviceState.pending.rawValue)
                .filter(CoachAdviceRecord.Columns.messageID != messageID)
                .updateAll(db, Column("state").set(to: CoachAdviceRecord.AdviceState.superseded.rawValue))
        }
    }

    /// Mark pending advice as ignored if no matching session appears within 48 hours.
    public func expireStalePending(olderThan deadline: Date) throws {
        try pool.write { db in
            try CoachAdviceRecord
                .filter(CoachAdviceRecord.Columns.state == CoachAdviceRecord.AdviceState.pending.rawValue)
                .filter(CoachAdviceRecord.Columns.createdAt < deadline)
                .updateAll(db, Column("state").set(to: CoachAdviceRecord.AdviceState.ignored.rawValue))
        }
    }
}
