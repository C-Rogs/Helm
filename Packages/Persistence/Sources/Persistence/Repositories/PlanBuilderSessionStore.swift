import Core
import Foundation
import GRDB

/// Persisted plan-builder flow state: interview answers plus generated candidates
/// and the selection, so the flow survives app restarts mid-way.
public struct StoredPlanBuilderSession: Sendable, Hashable, Codable {
    public var interview: PlanBuilderInterview
    public var selectedCandidateIndex: Int?
    /// Serialized candidate summaries, reserved for resume-with-copy support.
    public var candidateSummariesJSON: [String]

    public init(
        interview: PlanBuilderInterview,
        selectedCandidateIndex: Int? = nil,
        candidateSummariesJSON: [String] = []
    ) {
        self.interview = interview
        self.selectedCandidateIndex = selectedCandidateIndex
        self.candidateSummariesJSON = candidateSummariesJSON
    }

    enum CodingKeys: String, CodingKey {
        case interview
        case selectedCandidateIndex
        case candidateSummariesJSON
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        interview = try container.decode(PlanBuilderInterview.self, forKey: .interview)
        selectedCandidateIndex = try container.decodeIfPresent(Int.self, forKey: .selectedCandidateIndex)
        candidateSummariesJSON = try container.decodeIfPresent([String].self, forKey: .candidateSummariesJSON) ?? []
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
