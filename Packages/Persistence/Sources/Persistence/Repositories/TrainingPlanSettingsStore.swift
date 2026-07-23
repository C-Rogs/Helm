import Core
import Foundation
import GRDB

/// Persisted training phase/goal and experience for prescription and onboarding reuse.
public struct StoredTrainingPlanSettings: Sendable, Hashable, Codable {
    public var phaseGoal: PhaseGoal
    /// `TrainingExperience` raw value from PlanKit.
    public var experienceRaw: String

    public init(
        phaseGoal: PhaseGoal = PhaseGoal(phase: .maintain),
        experienceRaw: String = "intermediate"
    ) {
        self.phaseGoal = phaseGoal
        self.experienceRaw = experienceRaw
    }

    public static let `default` = StoredTrainingPlanSettings()
}

public struct TrainingPlanSettingsStore: Sendable {
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

    public func load() throws -> StoredTrainingPlanSettings {
        try pool.read { db in
            guard let record = try TrainingPlanSettingsRecord.fetchOne(db, key: TrainingPlanSettingsRecord.singletonID) else {
                return .default
            }
            let data = Data(record.settingsJSON.utf8)
            return try decoder.decode(StoredTrainingPlanSettings.self, from: data)
        }
    }

    public func save(_ settings: StoredTrainingPlanSettings, updatedAt: Date = Date()) throws {
        let data = try encoder.encode(settings)
        guard let json = String(data: data, encoding: .utf8) else {
            throw PersistenceError.migrationFailed("training plan settings JSON encoding failed")
        }
        try pool.write { db in
            try TrainingPlanSettingsRecord(settingsJSON: json, updatedAt: updatedAt).save(db)
        }
    }
}
