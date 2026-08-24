import CoachLLM
import Foundation
import GRDB

public struct StoredChatMessage: Sendable, Hashable, Identifiable, Equatable {
    public let id: String
    public let role: CoachMessage.Role
    public let text: String
    public let promptVersion: String
    public let schemaVersion: String?
    public let createdAt: Date
    public let sortIndex: Int

    public init(
        id: String,
        role: CoachMessage.Role,
        text: String,
        promptVersion: String,
        schemaVersion: String?,
        createdAt: Date,
        sortIndex: Int
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.promptVersion = promptVersion
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.sortIndex = sortIndex
    }
}

public struct ChatMessageInsert: Sendable, Equatable {
    public let role: CoachMessage.Role
    public let text: String
    public let promptVersion: String
    public let schemaVersion: String?

    public init(
        role: CoachMessage.Role,
        text: String,
        promptVersion: String,
        schemaVersion: String? = nil
    ) {
        self.role = role
        self.text = text
        self.promptVersion = promptVersion
        self.schemaVersion = schemaVersion
    }
}

public struct ChatStore: Sendable {
    private let pool: DatabasePool

    init(pool: DatabasePool) {
        self.pool = pool
    }

    public func fetchAll() throws -> [StoredChatMessage] {
        try pool.read { db in
            let records = try ChatMessageRecord
                .order(Column("sort_index"))
                .fetchAll(db)
            return try records.map { try $0.toValue() }
        }
    }

    /// Loads the most recent messages, oldest first.
    public func fetchRecent(limit: Int) throws -> [StoredChatMessage] {
        let cappedLimit = max(1, limit)
        return try pool.read { db in
            let records = try ChatMessageRecord
                .order(Column("sort_index").desc)
                .limit(cappedLimit)
                .fetchAll(db)
            return try records.reversed().map { try $0.toValue() }
        }
    }

    public func append(_ message: ChatMessageInsert, createdAt: Date = Date()) throws -> StoredChatMessage {
        try pool.write { db in
            let nextSortIndex = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(sort_index), -1) + 1 FROM chat_message"
            ) ?? 0
            let record = ChatMessageRecord(
                id: UUID().uuidString.lowercased(),
                role: message.role.rawValue,
                text: message.text,
                promptVersion: message.promptVersion,
                schemaVersion: message.schemaVersion,
                createdAt: ISO8601Coding.string(from: createdAt),
                sortIndex: nextSortIndex
            )
            try record.insert(db)
            return try record.toValue()
        }
    }

    public func clear() throws {
        _ = try pool.write { db in
            try ChatMessageRecord.deleteAll(db)
        }
    }
}

private extension ChatMessageRecord {
    func toValue() throws -> StoredChatMessage {
        guard let role = CoachMessage.Role(rawValue: role) else {
            throw PersistenceError.migrationFailed("unknown chat role: \(role)")
        }
        return StoredChatMessage(
            id: id,
            role: role,
            text: text,
            promptVersion: promptVersion,
            schemaVersion: schemaVersion,
            createdAt: try ISO8601Coding.date(from: createdAt),
            sortIndex: sortIndex
        )
    }
}
