import Foundation
import GRDB

public final class CoachAppliedActionStore: Sendable {
    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    public func insert(_ record: CoachAppliedAction) throws {
        var record = record
        try pool.write { db in
            try record.insert(db)
        }
    }

    public func fetchUndoable(messageID: String) throws -> CoachAppliedAction? {
        try pool.read { db in
            try CoachAppliedAction
                .filter(CoachAppliedAction.Columns.messageID == messageID)
                .filter(CoachAppliedAction.Columns.undoneAt == nil)
                .order(CoachAppliedAction.Columns.createdAt.desc)
                .fetchOne(db)
        }
    }

    public func fetch(id: UUID) throws -> CoachAppliedAction? {
        try pool.read { db in
            try CoachAppliedAction
                .filter(CoachAppliedAction.Columns.id == id.uuidString)
                .fetchOne(db)
        }
    }

    public func markUndone(id: UUID, at date: Date = .now) throws {
        try pool.write { db in
            guard var record = try CoachAppliedAction
                .filter(CoachAppliedAction.Columns.id == id.uuidString)
                .fetchOne(db)
            else { return }
            record.undoneAt = date
            try record.update(db)
        }
    }
}
