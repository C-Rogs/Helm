import CoachLLM
import Foundation
import GRDB

public enum ChatSurface: String, Sendable, Hashable, Equatable {
    case chat
    case train
}

public struct StoredChatMessage: Sendable, Hashable, Identifiable, Equatable {
    public let id: String
    public let role: CoachMessage.Role
    public let text: String
    public let promptVersion: String
    public let schemaVersion: String?
    public let createdAt: Date
    public let sortIndex: Int
    public let surface: ChatSurface

    public init(
        id: String,
        role: CoachMessage.Role,
        text: String,
        promptVersion: String,
        schemaVersion: String?,
        createdAt: Date,
        sortIndex: Int,
        surface: ChatSurface = .chat
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.promptVersion = promptVersion
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.sortIndex = sortIndex
        self.surface = surface
    }
}

public struct ChatMessageInsert: Sendable, Equatable {
    public let role: CoachMessage.Role
    public let text: String
    public let promptVersion: String
    public let schemaVersion: String?
    public let surface: ChatSurface

    public init(
        role: CoachMessage.Role,
        text: String,
        promptVersion: String,
        schemaVersion: String? = nil,
        surface: ChatSurface = .chat
    ) {
        self.role = role
        self.text = text
        self.promptVersion = promptVersion
        self.schemaVersion = schemaVersion
        self.surface = surface
    }
}

public struct ChatStore: Sendable {
    /// Train Ask Coach has no "clear chat". Keep a rolling window so SQLite does not grow without bound.
    public static let trainRetentionLimit = 200

    private let pool: DatabasePool

    init(pool: DatabasePool) {
        self.pool = pool
    }

    public func fetchAll(surface: ChatSurface = .chat) throws -> [StoredChatMessage] {
        try pool.read { db in
            let records = try ChatMessageRecord
                .filter(Column("surface") == surface.rawValue)
                .order(Column("sort_index"))
                .fetchAll(db)
            return try records.map { try $0.toValue() }
        }
    }

    /// Loads the most recent messages, oldest first.
    public func fetchRecent(limit: Int, surface: ChatSurface = .chat) throws -> [StoredChatMessage] {
        let cappedLimit = max(1, limit)
        return try pool.read { db in
            let records = try ChatMessageRecord
                .filter(Column("surface") == surface.rawValue)
                .order(Column("sort_index").desc)
                .limit(cappedLimit)
                .fetchAll(db)
            return try records.reversed().map { try $0.toValue() }
        }
    }

    public func append(
        _ message: ChatMessageInsert,
        createdAt: Date = Date(),
        keepingNewest: Int? = nil
    ) throws -> StoredChatMessage {
        try pool.write { db in
            let nextSortIndex = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(sort_index), -1) + 1 FROM chat_message WHERE surface = ?",
                arguments: [message.surface.rawValue]
            ) ?? 0
            let record = ChatMessageRecord(
                id: UUID().uuidString.lowercased(),
                role: message.role.rawValue,
                text: message.text,
                promptVersion: message.promptVersion,
                schemaVersion: message.schemaVersion,
                createdAt: ISO8601Coding.string(from: createdAt),
                sortIndex: nextSortIndex,
                surface: message.surface.rawValue
            )
            try record.insert(db)
            let retention = keepingNewest ?? (message.surface == .train ? Self.trainRetentionLimit : nil)
            if let retention {
                try Self.trimOldest(db: db, surface: message.surface, keepingNewest: retention)
            }
            return try record.toValue()
        }
    }

    public func clear(surface: ChatSurface = .chat) throws {
        _ = try pool.write { db in
            try ChatMessageRecord
                .filter(Column("surface") == surface.rawValue)
                .deleteAll(db)
        }
    }

    private static func trimOldest(db: Database, surface: ChatSurface, keepingNewest: Int) throws {
        let keep = max(1, keepingNewest)
        let count = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM chat_message WHERE surface = ?",
            arguments: [surface.rawValue]
        ) ?? 0
        let excess = count - keep
        guard excess > 0 else { return }
        try db.execute(
            sql: """
                DELETE FROM chat_message
                WHERE id IN (
                    SELECT id FROM chat_message
                    WHERE surface = ?
                    ORDER BY sort_index ASC
                    LIMIT ?
                )
                """,
            arguments: [surface.rawValue, excess]
        )
    }
}

private extension ChatMessageRecord {
    func toValue() throws -> StoredChatMessage {
        guard let role = CoachMessage.Role(rawValue: role) else {
            throw PersistenceError.migrationFailed("unknown chat role: \(role)")
        }
        let resolvedSurface = ChatSurface(rawValue: self.surface) ?? .chat
        return StoredChatMessage(
            id: id,
            role: role,
            text: text,
            promptVersion: promptVersion,
            schemaVersion: schemaVersion,
            createdAt: try ISO8601Coding.date(from: createdAt),
            sortIndex: sortIndex,
            surface: resolvedSurface
        )
    }
}
