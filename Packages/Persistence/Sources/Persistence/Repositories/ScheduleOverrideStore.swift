import Core
import Foundation
import GRDB

/// Week-scoped schedule edits: pin day kinds, defer recovery conflicts, force rest.
/// Does not change permanent program rotation.
public struct StoredScheduleOverrides: Sendable, Hashable, Codable, Equatable {
    /// ISO week start (`HelmDay.formatted`) this override applies to.
    public var weekStartFormatted: String
    /// Explicit day → `TrainingDayKind` raw value pins.
    public var pinnedByDay: [String: String]
    /// Day kinds to skip when picking the next rotation slot.
    public var deferredKinds: [String]
    /// Calendar days forced to Rest (session moved elsewhere).
    public var restDays: [String]
    public var reason: String?

    public init(
        weekStartFormatted: String = "",
        pinnedByDay: [String: String] = [:],
        deferredKinds: [String] = [],
        restDays: [String] = [],
        reason: String? = nil
    ) {
        self.weekStartFormatted = weekStartFormatted
        self.pinnedByDay = pinnedByDay
        self.deferredKinds = deferredKinds
        self.restDays = restDays
        self.reason = reason
    }

    public static let empty = StoredScheduleOverrides()

    public func isActive(forWeekStarting weekStart: HelmDay) -> Bool {
        !weekStartFormatted.isEmpty && weekStartFormatted == weekStart.formatted
    }

    public var isEmpty: Bool {
        pinnedByDay.isEmpty && deferredKinds.isEmpty && restDays.isEmpty
    }
}

public struct ScheduleOverrideStore: Sendable {
    private let pool: DatabasePool
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(pool: DatabasePool) {
        self.pool = pool
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    public func load() throws -> StoredScheduleOverrides {
        try pool.read { db in
            guard let record = try ScheduleOverrideRecord.fetchOne(db, key: ScheduleOverrideRecord.singletonID) else {
                return .empty
            }
            let data = Data(record.overridesJSON.utf8)
            return try decoder.decode(StoredScheduleOverrides.self, from: data)
        }
    }

    public func save(_ overrides: StoredScheduleOverrides, updatedAt: Date = Date()) throws {
        let data = try encoder.encode(overrides)
        guard let json = String(data: data, encoding: .utf8) else {
            throw PersistenceError.migrationFailed("schedule override JSON encoding failed")
        }
        try pool.write { db in
            try ScheduleOverrideRecord(overridesJSON: json, updatedAt: updatedAt).save(db)
        }
    }

    public func clear() throws {
        try save(.empty)
    }
}
