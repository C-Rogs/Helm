import Core
import Foundation
import GRDB

/// Persisted training phase/goal and experience for prescription and onboarding reuse.
public struct StoredTrainingPlanSettings: Sendable, Hashable, Codable {
    public var phaseGoal: PhaseGoal
    /// `TrainingExperience` raw value from PlanKit.
    public var experienceRaw: String
    /// `ProgramTemplate` raw value from PlanKit (`ppl`, `upper_lower`, `full_body`).
    public var programTemplateRaw: String
    /// Session duration budget in minutes (30 / 45 / 60 / 75).
    public var sessionDurationMinutes: Int
    /// Training days available per week (2...6). Defaults to the legacy 3-day rotation.
    public var daysPerWeek: Int
    /// Ordered `TrainingDayKind` raw values for one week. Empty means derive from template + daysPerWeek.
    public var dayKindRotationRaw: [String]

    public init(
        phaseGoal: PhaseGoal = PhaseGoal(phase: .maintain),
        experienceRaw: String = "intermediate",
        programTemplateRaw: String = "ppl",
        sessionDurationMinutes: Int = 60,
        daysPerWeek: Int = SchedulePlannerConstants.defaultSessionsPerWeek,
        dayKindRotationRaw: [String] = []
    ) {
        self.phaseGoal = phaseGoal
        self.experienceRaw = experienceRaw
        self.programTemplateRaw = programTemplateRaw
        self.sessionDurationMinutes = sessionDurationMinutes
        self.daysPerWeek = min(max(daysPerWeek, 2), 6)
        self.dayKindRotationRaw = dayKindRotationRaw
    }

    public static let `default` = StoredTrainingPlanSettings()

    enum CodingKeys: String, CodingKey {
        case phaseGoal
        case experienceRaw
        case programTemplateRaw
        case sessionDurationMinutes
        case daysPerWeek
        case dayKindRotationRaw
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phaseGoal = try container.decode(PhaseGoal.self, forKey: .phaseGoal)
        experienceRaw = try container.decodeIfPresent(String.self, forKey: .experienceRaw) ?? "intermediate"
        programTemplateRaw = try container.decodeIfPresent(String.self, forKey: .programTemplateRaw) ?? "ppl"
        sessionDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .sessionDurationMinutes) ?? 60
        daysPerWeek = try container.decodeIfPresent(Int.self, forKey: .daysPerWeek)
            ?? SchedulePlannerConstants.defaultSessionsPerWeek
        dayKindRotationRaw = try container.decodeIfPresent([String].self, forKey: .dayKindRotationRaw) ?? []
    }
}

/// Local constant so Persistence does not depend on HealthKitIngest's SchedulePlanner.
public enum SchedulePlannerConstants {
    public static let defaultSessionsPerWeek = 3
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
