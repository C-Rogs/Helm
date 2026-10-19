import Foundation
import GRDB

public final class CoachChatConfirmationStore: Sendable {
    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    public func insert(_ record: CoachChatConfirmation) throws {
        var record = record
        try pool.write { db in
            try record.insert(db)
        }
    }

    public func upsert(_ record: CoachChatConfirmation) throws {
        var record = record
        try pool.write { db in
            try record.save(db)
        }
    }

    public func fetch(messageID: String) throws -> CoachChatConfirmation? {
        try pool.read { db in
            try CoachChatConfirmation
                .filter(CoachChatConfirmation.Columns.messageID == messageID)
                .order(CoachChatConfirmation.Columns.createdAt.desc)
                .fetchOne(db)
        }
    }

    public func fetch(forMessageIDs ids: [String]) throws -> [CoachChatConfirmation] {
        guard !ids.isEmpty else { return [] }
        return try pool.read { db in
            try CoachChatConfirmation
                .filter(ids.contains(CoachChatConfirmation.Columns.messageID))
                .fetchAll(db)
        }
    }

    public func markResolved(
        messageID: String,
        outcome: CoachChatConfirmation.Outcome,
        selectedLabel: String
    ) throws {
        try pool.write { db in
            guard var record = try CoachChatConfirmation
                .filter(CoachChatConfirmation.Columns.messageID == messageID)
                .order(CoachChatConfirmation.Columns.createdAt.desc)
                .fetchOne(db)
            else { return }
            record.outcome = outcome
            record.selectedLabel = selectedLabel
            record.resolvedAt = .now
            try record.update(db)
        }
    }

    public func clearAll() throws {
        try pool.write { db in
            _ = try CoachChatConfirmation.deleteAll(db)
        }
    }
}
