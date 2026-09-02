import Core
import Foundation
import GRDB

/// One applied coach write that can be undone from the chat transcript.
public struct CoachAppliedAction: Sendable, Identifiable, Equatable {
    public enum Kind: String, Sendable, Codable, Equatable {
        case mealDelete
    }

    public var id: UUID
    public var messageID: String
    public var kind: Kind
    public var snapshotJSON: String
    public var undoneAt: Date?
    public var createdAt: Date

    public var isUndoable: Bool { undoneAt == nil }

    public init(
        id: UUID = UUID(),
        messageID: String,
        kind: Kind,
        snapshotJSON: String,
        undoneAt: Date? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.messageID = messageID
        self.kind = kind
        self.snapshotJSON = snapshotJSON
        self.undoneAt = undoneAt
        self.createdAt = createdAt
    }
}

public struct MealDeleteSnapshot: Sendable, Codable, Equatable {
    public struct Item: Sendable, Codable, Equatable {
        public var meal: MealRecord
        public var lineItems: [MealLineItemRecord]

        public init(meal: MealRecord, lineItems: [MealLineItemRecord]) {
            self.meal = meal
            self.lineItems = lineItems
        }
    }

    public var items: [Item]

    public init(items: [Item]) {
        self.items = items
    }
}

extension CoachAppliedAction: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "coach_applied_action"

    enum Columns {
        static let id = Column("id")
        static let messageID = Column("message_id")
        static let kind = Column("kind")
        static let snapshotJSON = Column("snapshot_json")
        static let undoneAt = Column("undone_at")
        static let createdAt = Column("created_at")
    }

    public func encode(to container: inout PersistenceContainer) {
        container[Columns.id.name] = id.uuidString
        container[Columns.messageID.name] = messageID
        container[Columns.kind.name] = kind.rawValue
        container[Columns.snapshotJSON.name] = snapshotJSON
        container[Columns.undoneAt.name] = undoneAt.map(ISO8601Coding.string(from:))
        container[Columns.createdAt.name] = ISO8601Coding.string(from: createdAt)
    }

    public init(row: Row) throws {
        let idString: String = row[Columns.id]
        guard let parsedID = UUID(uuidString: idString) else {
            throw PersistenceError.migrationFailed("invalid coach applied action id: \(idString)")
        }
        id = parsedID
        messageID = row[Columns.messageID]
        let kindRaw: String = row[Columns.kind]
        guard let parsedKind = Kind(rawValue: kindRaw) else {
            throw PersistenceError.migrationFailed("unknown coach applied action kind: \(kindRaw)")
        }
        kind = parsedKind
        snapshotJSON = row[Columns.snapshotJSON]
        if let undoneRaw: String = row[Columns.undoneAt] {
            undoneAt = try ISO8601Coding.date(from: undoneRaw)
        } else {
            undoneAt = nil
        }
        createdAt = try ISO8601Coding.date(from: row[Columns.createdAt])
    }
}
