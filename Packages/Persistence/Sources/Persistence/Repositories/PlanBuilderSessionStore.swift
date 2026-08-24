import Core
import Foundation
import GRDB

/// One restorable plan option: candidate stats plus its card copy.
public struct StoredPlanBuilderOption: Sendable, Hashable, Codable {
    /// Serialized `CandidatePlan`.
    public var encodedCandidate: String
    /// Serialized `PlanOptionCardCopy`.
    public var encodedCopy: String

    public init(encodedCandidate: String, encodedCopy: String) {
        self.encodedCandidate = encodedCandidate
        self.encodedCopy = encodedCopy
    }
}

/// Persisted plan-builder flow state: interview answers plus generated options
/// and the selection, so the flow survives app restarts mid-way.
public struct StoredPlanBuilderSession: Sendable, Hashable, Codable {
    public var interview: PlanBuilderInterview
    public var selectedCandidateIndex: Int?
    /// Generated options captured after a successful generation pass.
    public var options: [StoredPlanBuilderOption]

    public init(
        interview: PlanBuilderInterview,
        selectedCandidateIndex: Int? = nil,
        options: [StoredPlanBuilderOption] = []
    ) {
        self.interview = interview
        self.selectedCandidateIndex = selectedCandidateIndex
        self.options = options
    }

    enum CodingKeys: String, CodingKey {
        case interview
        case selectedCandidateIndex
        case options
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        interview = try container.decode(PlanBuilderInterview.self, forKey: .interview)
        selectedCandidateIndex = try container.decodeIfPresent(Int.self, forKey: .selectedCandidateIndex)
        options = try container.decodeIfPresent([StoredPlanBuilderOption].self, forKey: .options) ?? []
    }
}

struct PlanBuilderSessionRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "plan_builder_session"
    static let singletonID: Int64 = 1

    var id: Int64
    var sessionJSON: String
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case sessionJSON = "session_json"
        case updatedAt = "updated_at"
    }

    init(sessionJSON: String, updatedAt: Date) {
        id = Self.singletonID
        self.sessionJSON = sessionJSON
        self.updatedAt = updatedAt
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct PlanBuilderSessionStore: Sendable {
    private let pool: DatabasePool
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(pool: DatabasePool) {
        self.pool = pool
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    public func load() throws -> StoredPlanBuilderSession? {
        try pool.read { db in
            guard let record = try PlanBuilderSessionRecord.fetchOne(db, key: PlanBuilderSessionRecord.singletonID) else {
                return nil
            }
            let data = Data(record.sessionJSON.utf8)
            return try decoder.decode(StoredPlanBuilderSession.self, from: data)
        }
    }

    public func save(_ session: StoredPlanBuilderSession, updatedAt: Date = Date()) throws {
        let data = try encoder.encode(session)
        guard let json = String(data: data, encoding: .utf8) else {
            throw PersistenceError.migrationFailed("plan builder session JSON encoding failed")
        }
        try pool.write { db in
            var record = PlanBuilderSessionRecord(sessionJSON: json, updatedAt: updatedAt)
            try record.save(db)
        }
    }

    public func clear() throws {
        _ = try pool.write { db in
            try PlanBuilderSessionRecord.deleteOne(db, key: PlanBuilderSessionRecord.singletonID)
        }
    }
}
