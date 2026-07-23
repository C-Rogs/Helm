import Foundation
import GRDB

public actor PersistenceStore {
    public nonisolated let dailyMetrics: DailyMetricsRepository
    public nonisolated let bodyComposition: BodyCompositionRepository
    public nonisolated let sleep: SleepRepository
    public nonisolated let nutrition: NutritionRepository
    public nonisolated let exercises: ExerciseRepository
    public nonisolated let workoutSessions: WorkoutSessionRepository
    public nonisolated let workoutTemplates: WorkoutTemplateRepository
    public nonisolated let personalRecords: PersonalRecordRepository
    public nonisolated let readiness: ReadinessRepository
    public nonisolated let memoryProfile: MemoryProfileStore
    public nonisolated let plan: PlanRepository
    public nonisolated let trainingPlan: TrainingPlanSettingsStore
    public nonisolated let activeSessions: ActiveSessionRepository
    public nonisolated let chat: ChatStore
    public nonisolated let brief: BriefStore
    public nonisolated let coachRecommendations: CoachRecommendationRepository

    public let databaseURL: URL
    private let pool: DatabasePool

    internal nonisolated var poolForTesting: DatabasePool { pool }

    public init(pool: DatabasePool, databaseURL: URL) {
        self.pool = pool
        self.databaseURL = databaseURL
        dailyMetrics = DailyMetricsRepository(pool: pool)
        bodyComposition = BodyCompositionRepository(pool: pool)
        sleep = SleepRepository(pool: pool)
        nutrition = NutritionRepository(pool: pool)
        exercises = ExerciseRepository(pool: pool)
        workoutSessions = WorkoutSessionRepository(pool: pool)
        workoutTemplates = WorkoutTemplateRepository(pool: pool)
        personalRecords = PersonalRecordRepository(pool: pool)
        readiness = ReadinessRepository(pool: pool)
        memoryProfile = MemoryProfileStore(pool: pool)
        plan = PlanRepository(pool: pool)
        trainingPlan = TrainingPlanSettingsStore(pool: pool)
        activeSessions = ActiveSessionRepository(pool: pool)
        chat = ChatStore(pool: pool)
        brief = BriefStore(pool: pool)
        coachRecommendations = CoachRecommendationRepository(pool: pool)
    }

    public static func openDefault() throws -> PersistenceStore {
        let url = try DatabaseLocation.defaultDatabaseURL()
        return try open(at: url)
    }

    public static func open(at url: URL) throws -> PersistenceStore {
        let pool = try DatabaseFactory.makePool(at: url)
        try AppMigrator().migrate(pool)
        return PersistenceStore(pool: pool, databaseURL: url)
    }

    public static func inMemory() throws -> PersistenceStore {
        let pool = try DatabaseFactory.makeInMemoryPool()
        try AppMigrator().migrate(pool)
        let url = URL(fileURLWithPath: pool.path)
        return PersistenceStore(pool: pool, databaseURL: url)
    }

    public nonisolated var schemaVersion: Int {
        SchemaVersion.latest
    }

    public nonisolated func exerciseSeedVersion() throws -> Int {
        try ExerciseSeedImporter(pool: pool).appliedSeedVersion()
    }

    public func importExerciseSeedIfNeeded(manifestURL: URL) throws -> ExerciseSeedImportResult {
        try ExerciseSeedImporter(pool: pool).importIfNeeded(manifestURL: manifestURL)
    }

    public func checkpoint() throws {
        _ = try pool.writeWithoutTransaction { db in
            try db.checkpoint(.passive)
        }
    }

    public func exportCheckpointedCopy() throws -> URL {
        let destinationURL = Self.makeExportURL()
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        let backupPool = try DatabaseFactory.makePool(at: destinationURL)
        defer {
            try? backupPool.close()
        }
        try pool.backup(to: backupPool)
        return destinationURL
    }

    private static func makeExportURL() -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("helm-\(timestamp).sqlite")
    }
}
