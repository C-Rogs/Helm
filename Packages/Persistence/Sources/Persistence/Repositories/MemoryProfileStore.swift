import CoachLLM
import Foundation
import GRDB

public struct MemoryProfileStore: Sendable {
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

    public func load() throws -> MemoryProfile {
        try pool.read { db in
            guard let record = try MemoryProfileRecord.fetchOne(db, key: MemoryProfileRecord.singletonID) else {
                return .empty
            }
            let data = Data(record.profileJSON.utf8)
            return try decoder.decode(MemoryProfile.self, from: data)
        }
    }

    public func save(_ profile: MemoryProfile, updatedAt: Date = Date()) throws {
        let data = try encoder.encode(profile)
        guard let json = String(data: data, encoding: .utf8) else {
            throw PersistenceError.migrationFailed("memory profile JSON encoding failed")
        }
        try pool.write { db in
            try MemoryProfileRecord(profileJSON: json, updatedAt: updatedAt).save(db)
        }
    }
}
