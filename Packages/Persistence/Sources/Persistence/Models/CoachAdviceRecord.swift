import Foundation
import GRDB

/// Tracks whether the athlete acted on coach advice (workout prescriptions,
/// meal suggestions, etc.).
public struct CoachAdviceRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public var id: UUID
    public var messageID: String
    public var adviceType: AdviceType
    public var schemaVersion: String
    public var prescribedPayload: String
    public var state: AdviceState
    public var linkedSessionID: String?
    public var helmDay: String
    public var createdAt: Date

    public enum AdviceType: String, Codable {
        case workoutStart
        case foodLog
        case settingsAdjustment
        case memoryAdjustment
        case reactiveDeload
    }

    public enum AdviceState: String, Codable {
        case pending
        case actedOn
        case ignored
        case superseded
    }

    public init(
        id: UUID = UUID(),
        messageID: String,
        adviceType: AdviceType,
        schemaVersion: String,
        prescribedPayload: String,
        state: AdviceState = .pending,
        linkedSessionID: String? = nil,
        helmDay: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.messageID = messageID
        self.adviceType = adviceType
        self.schemaVersion = schemaVersion
        self.prescribedPayload = prescribedPayload
        self.state = state
        self.linkedSessionID = linkedSessionID
        self.helmDay = helmDay
        self.createdAt = createdAt
    }
}

// MARK: - Table definition

extension CoachAdviceRecord {
    public static let databaseTableName = "coach_advice_record"

    enum CodingKeys: String, CodingKey {
        case id
        case messageID = "message_id"
        case adviceType = "advice_type"
        case schemaVersion = "schema_version"
        case prescribedPayload = "prescribed_payload"
        case state
        case linkedSessionID = "linked_session_id"
        case helmDay = "helm_day"
        case createdAt = "created_at"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let messageID = Column(CodingKeys.messageID)
        static let adviceType = Column(CodingKeys.adviceType)
        static let schemaVersion = Column(CodingKeys.schemaVersion)
        static let prescribedPayload = Column(CodingKeys.prescribedPayload)
        static let state = Column(CodingKeys.state)
        static let linkedSessionID = Column(CodingKeys.linkedSessionID)
        static let helmDay = Column(CodingKeys.helmDay)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    public func encode(to container: inout PersistenceContainer) {
        container[Columns.id.name] = id.uuidString
        container[Columns.messageID.name] = messageID
        container[Columns.adviceType.name] = adviceType.rawValue
        container[Columns.schemaVersion.name] = schemaVersion
        container[Columns.prescribedPayload.name] = prescribedPayload
        container[Columns.state.name] = state.rawValue
        container[Columns.linkedSessionID.name] = linkedSessionID
        container[Columns.helmDay.name] = helmDay
        container[Columns.createdAt.name] = ISO8601Coding.string(from: createdAt)
    }

    public init(row: Row) throws {
        let idString: String = row[Columns.id]
        guard let parsedID = UUID(uuidString: idString) else {
            throw PersistenceError.migrationFailed("invalid coach advice id: \(idString)")
        }
        id = parsedID
        messageID = row[Columns.messageID]
        let typeRaw: String = row[Columns.adviceType]
        guard let parsedType = AdviceType(rawValue: typeRaw) else {
            throw PersistenceError.migrationFailed("unknown coach advice type: \(typeRaw)")
        }
        adviceType = parsedType
        schemaVersion = row[Columns.schemaVersion]
        prescribedPayload = row[Columns.prescribedPayload]
        let stateRaw: String = row[Columns.state]
        guard let parsedState = AdviceState(rawValue: stateRaw) else {
            throw PersistenceError.migrationFailed("unknown coach advice state: \(stateRaw)")
        }
        state = parsedState
        linkedSessionID = row[Columns.linkedSessionID]
        helmDay = row[Columns.helmDay]
        createdAt = try ISO8601Coding.date(from: row[Columns.createdAt])
    }
}
