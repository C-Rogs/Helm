import Foundation
import GRDB

/// Display snapshot of a coach confirm card anchored to an assistant chat message (CAM-86).
public struct CoachChatConfirmation: Sendable, Identifiable, Equatable {
    public enum Outcome: String, Sendable, Codable, Equatable {
        case pending
        case confirmed
        case dismissed
    }

    public var id: UUID
    public var messageID: String
    public var title: String
    public var detail: String
    public var reason: String?
    public var confirmLabel: String
    public var cancelLabel: String
    public var outcome: Outcome
    public var selectedLabel: String?
    public var createdAt: Date
    public var resolvedAt: Date?

    public var isPending: Bool { outcome == .pending }

    public init(
        id: UUID = UUID(),
        messageID: String,
        title: String,
        detail: String,
        reason: String? = nil,
        confirmLabel: String,
        cancelLabel: String,
        outcome: Outcome = .pending,
        selectedLabel: String? = nil,
        createdAt: Date = .now,
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.messageID = messageID
        self.title = title
        self.detail = detail
        self.reason = reason
        self.confirmLabel = confirmLabel
        self.cancelLabel = cancelLabel
        self.outcome = outcome
        self.selectedLabel = selectedLabel
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
    }
}

extension CoachChatConfirmation: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "coach_chat_confirmation"

    enum Columns {
        static let id = Column("id")
        static let messageID = Column("message_id")
        static let title = Column("title")
        static let detail = Column("detail")
        static let reason = Column("reason")
        static let confirmLabel = Column("confirm_label")
        static let cancelLabel = Column("cancel_label")
        static let outcome = Column("outcome")
        static let selectedLabel = Column("selected_label")
        static let createdAt = Column("created_at")
        static let resolvedAt = Column("resolved_at")
    }

    public func encode(to container: inout PersistenceContainer) {
        container[Columns.id.name] = id.uuidString
        container[Columns.messageID.name] = messageID
        container[Columns.title.name] = title
        container[Columns.detail.name] = detail
        container[Columns.reason.name] = reason
        container[Columns.confirmLabel.name] = confirmLabel
        container[Columns.cancelLabel.name] = cancelLabel
        container[Columns.outcome.name] = outcome.rawValue
        container[Columns.selectedLabel.name] = selectedLabel
        container[Columns.createdAt.name] = ISO8601Coding.string(from: createdAt)
        container[Columns.resolvedAt.name] = resolvedAt.map(ISO8601Coding.string(from:))
    }

    public init(row: Row) throws {
        let idString: String = row[Columns.id]
        guard let parsedID = UUID(uuidString: idString) else {
            throw PersistenceError.migrationFailed("invalid coach chat confirmation id: \(idString)")
        }
        id = parsedID
        messageID = row[Columns.messageID]
        title = row[Columns.title]
        detail = row[Columns.detail]
        reason = row[Columns.reason]
        confirmLabel = row[Columns.confirmLabel]
        cancelLabel = row[Columns.cancelLabel]
        let outcomeRaw: String = row[Columns.outcome]
        guard let parsedOutcome = Outcome(rawValue: outcomeRaw) else {
            throw PersistenceError.migrationFailed("unknown coach chat confirmation outcome: \(outcomeRaw)")
        }
        outcome = parsedOutcome
        selectedLabel = row[Columns.selectedLabel]
        createdAt = try ISO8601Coding.date(from: row[Columns.createdAt])
        if let resolvedRaw: String = row[Columns.resolvedAt] {
            resolvedAt = try ISO8601Coding.date(from: resolvedRaw)
        } else {
            resolvedAt = nil
        }
    }
}
