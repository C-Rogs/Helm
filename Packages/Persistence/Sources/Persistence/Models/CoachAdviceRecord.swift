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
    public static let databaseTableName = "coachAdviceRecord"

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
}
