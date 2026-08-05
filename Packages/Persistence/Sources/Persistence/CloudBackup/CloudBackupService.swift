import CoachLLM
import Core
import Foundation

/// Builds, sizes, pushes, and pulls profile (+ optional 90-day history) backups.
public struct CloudBackupService: Sendable {
    public static let bodyProfileMetadataKey = "body_profile"
    public static let defaultLookbackDays = TrainingHistoryExportService.defaultLookbackDays

    private let store: PersistenceStore
    private let fileStore: any CloudBackupFileStore
    private let historyService: TrainingHistoryExportService
    private let fileEncoder: JSONEncoder
    private let fileDecoder: JSONDecoder
    private let metadataEncoder: JSONEncoder
    private let metadataDecoder: JSONDecoder

    public init(
        store: PersistenceStore,
        fileStore: any CloudBackupFileStore = UbiquityCloudBackupFileStore()
    ) {
        self.store = store
        self.fileStore = fileStore
        historyService = TrainingHistoryExportService(
            sessions: store.workoutSessions,
            exercises: store.exercises
        )
        let fileEncoder = JSONEncoder()
        fileEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        fileEncoder.dateEncodingStrategy = .iso8601
        self.fileEncoder = fileEncoder
        let fileDecoder = JSONDecoder()
        fileDecoder.dateDecodingStrategy = .iso8601
        self.fileDecoder = fileDecoder
        // Match BodyProfileStore (default date coding into app_metadata).
        metadataEncoder = JSONEncoder()
        metadataDecoder = JSONDecoder()
    }

    public var isAvailable: Bool { fileStore.isAvailable }

    public func buildProfileBackup(
        onboardingCompleted: Bool,
        updatedAt: Date = Date()
    ) throws -> HelmCloudProfileBackup {
        let memory = try store.memoryProfile.load()
        let plan = try store.trainingPlan.load()
        let meso = try store.plan.loadMesocycleStateJSON()
        let body = try loadBodyProfile()
        return HelmCloudProfileBackup(
            updatedAt: updatedAt,
            memoryProfile: memory,
            bodyProfile: body,
            trainingPlanSettings: plan,
            mesocycleStateJSON: meso,
            onboardingCompleted: onboardingCompleted
        )
    }

    public func encodeProfile(_ backup: HelmCloudProfileBackup) throws -> Data {
        do {
            return try fileEncoder.encode(backup)
        } catch {
            throw CloudBackupError.profileEncodingFailed
        }
    }

    public func decodeProfile(_ data: Data) throws -> HelmCloudProfileBackup {
        do {
            let backup = try fileDecoder.decode(HelmCloudProfileBackup.self, from: data)
            guard backup.schemaVersion == HelmCloudProfileBackup.currentSchemaVersion else {
                throw CloudBackupError.unsupportedProfileSchemaVersion(backup.schemaVersion)
            }
            return backup
        } catch let error as CloudBackupError {
            throw error
        } catch {
            throw CloudBackupError.profileDecodingFailed
        }
    }

    public func estimateSizes(
        onboardingCompleted: Bool,
        now: Date = Date()
    ) throws -> CloudBackupSizeEstimate {
        let profile = try buildProfileBackup(onboardingCompleted: onboardingCompleted, updatedAt: now)
        let profileData = try encodeProfile(profile)
        let history = try historyService.exportHistory(
            lookbackDays: Self.defaultLookbackDays,
            now: now
        )
        let historyData = try historyService.encode(history)
        return CloudBackupSizeEstimate(
            profileByteCount: profileData.count,
            historyByteCount: historyData.count,
            historySessionCount: history.sessions.count
        )
    }

    public func push(
        includeHistory: Bool,
        onboardingCompleted: Bool,
        now: Date = Date()
    ) throws -> CloudBackupPushResult {
        guard fileStore.isAvailable else { throw CloudBackupError.iCloudUnavailable }

        let profile = try buildProfileBackup(onboardingCompleted: onboardingCompleted, updatedAt: now)
        let profileData = try encodeProfile(profile)
        try fileStore.write(
            data: profileData,
            fileName: UbiquityCloudBackupFileStore.profileFileName
        )

        var historyByteCount: Int?
        var historySessionCount: Int?
        if includeHistory {
            let history = try historyService.exportHistory(
                lookbackDays: Self.defaultLookbackDays,
                now: now
            )
            let historyData = try historyService.encode(history)
            try fileStore.write(
                data: historyData,
                fileName: UbiquityCloudBackupFileStore.historyFileName
            )
            historyByteCount = historyData.count
            historySessionCount = history.sessions.count
        } else {
            try fileStore.remove(fileName: UbiquityCloudBackupFileStore.historyFileName)
        }

        return CloudBackupPushResult(
            profileUpdatedAt: profile.updatedAt,
            profileByteCount: profileData.count,
            historyByteCount: historyByteCount,
            historySessionCount: historySessionCount
        )
    }

    /// Last-write-wins restore. Applies profile when cloud `updatedAt` is newer than
    /// `lastAppliedProfileUpdatedAt`, or when `forceIfFreshInstall` and local has no sessions.
    public func pullIfNeeded(
        includeHistory: Bool,
        lastAppliedProfileUpdatedAt: Date?,
        forceIfFreshInstall: Bool,
        applyOnboardingCompleted: (Bool) -> Void
    ) throws -> CloudBackupPullResult {
        guard fileStore.isAvailable else { throw CloudBackupError.iCloudUnavailable }

        guard let profileData = try fileStore.read(
            fileName: UbiquityCloudBackupFileStore.profileFileName
        ) else {
            throw CloudBackupError.missingProfileBackup
        }
        let cloudProfile = try decodeProfile(profileData)

        let localIsFresh = try isFreshInstall()
        let shouldRestoreProfile: Bool
        if let lastApplied = lastAppliedProfileUpdatedAt {
            shouldRestoreProfile = cloudProfile.updatedAt > lastApplied
        } else {
            shouldRestoreProfile = forceIfFreshInstall && localIsFresh
        }

        if shouldRestoreProfile {
            try applyProfile(cloudProfile, applyOnboardingCompleted: applyOnboardingCompleted)
        }

        var historyImport: TrainingHistoryImportResult?
        if includeHistory,
           let historyData = try fileStore.read(
               fileName: UbiquityCloudBackupFileStore.historyFileName
           ) {
            let export = try historyService.decode(historyData)
            historyImport = try historyService.importHistory(export)
        }

        return CloudBackupPullResult(
            didRestoreProfile: shouldRestoreProfile,
            profileUpdatedAt: cloudProfile.updatedAt,
            historyImport: historyImport
        )
    }

    /// Force restore regardless of LWW (manual "Restore from iCloud").
    public func pullForced(
        includeHistory: Bool,
        applyOnboardingCompleted: (Bool) -> Void
    ) throws -> CloudBackupPullResult {
        guard fileStore.isAvailable else { throw CloudBackupError.iCloudUnavailable }

        guard let profileData = try fileStore.read(
            fileName: UbiquityCloudBackupFileStore.profileFileName
        ) else {
            throw CloudBackupError.missingProfileBackup
        }
        let cloudProfile = try decodeProfile(profileData)
        try applyProfile(cloudProfile, applyOnboardingCompleted: applyOnboardingCompleted)

        var historyImport: TrainingHistoryImportResult?
        if includeHistory,
           let historyData = try fileStore.read(
               fileName: UbiquityCloudBackupFileStore.historyFileName
           ) {
            let export = try historyService.decode(historyData)
            historyImport = try historyService.importHistory(export)
        }

        return CloudBackupPullResult(
            didRestoreProfile: true,
            profileUpdatedAt: cloudProfile.updatedAt,
            historyImport: historyImport
        )
    }

    public func peekCloudProfileUpdatedAt() throws -> Date? {
        guard fileStore.isAvailable else { return nil }
        guard let data = try fileStore.read(
            fileName: UbiquityCloudBackupFileStore.profileFileName
        ) else {
            return nil
        }
        return try decodeProfile(data).updatedAt
    }

    // MARK: - Private

    private func loadBodyProfile() throws -> BodyProfile? {
        guard let json = try store.appMetadata.value(forKey: Self.bodyProfileMetadataKey) else {
            return nil
        }
        guard let data = json.data(using: .utf8) else { return nil }
        return try? metadataDecoder.decode(BodyProfile.self, from: data)
    }

    private func saveBodyProfile(_ profile: BodyProfile?) throws {
        guard let profile, profile.isComplete else {
            try store.appMetadata.setValue(nil, forKey: Self.bodyProfileMetadataKey)
            return
        }
        let data = try metadataEncoder.encode(profile)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CloudBackupError.profileEncodingFailed
        }
        try store.appMetadata.setValue(json, forKey: Self.bodyProfileMetadataKey)
    }

    private func applyProfile(
        _ backup: HelmCloudProfileBackup,
        applyOnboardingCompleted: (Bool) -> Void
    ) throws {
        try store.memoryProfile.save(backup.memoryProfile, updatedAt: backup.updatedAt)
        try store.trainingPlan.save(backup.trainingPlanSettings, updatedAt: backup.updatedAt)
        if let meso = backup.mesocycleStateJSON {
            try store.plan.saveMesocycleStateJSON(meso, updatedAt: backup.updatedAt)
        }
        try saveBodyProfile(backup.bodyProfile)
        applyOnboardingCompleted(backup.onboardingCompleted)
    }

    private func isFreshInstall() throws -> Bool {
        let since = Date().addingTimeInterval(-Double(Self.defaultLookbackDays) * 86_400)
        let sessions = try store.workoutSessions.fetchCompletedSessions(since: since)
        if !sessions.isEmpty { return false }
        let memory = try store.memoryProfile.load()
        if memory != .empty { return false }
        return true
    }
}
