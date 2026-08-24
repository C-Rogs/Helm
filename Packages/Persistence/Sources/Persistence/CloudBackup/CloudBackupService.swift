import CoachLLM
import Core
import Foundation

/// Builds, sizes, pushes, and pulls profile (+ optional 90-day history) backups.
public struct CloudBackupService: Sendable {
    public static let bodyProfileMetadataKey = "body_profile"
    public static let defaultLookbackDays = TrainingHistoryExportService.defaultLookbackDays
    /// Wait for large history files to download from iCloud on fresh installs.
    public static let iCloudDownloadTimeout: TimeInterval = 45

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
            guard backup.schemaVersion <= HelmCloudProfileBackup.currentSchemaVersion else {
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
        let nutrition = try buildNutritionBackup(now: now)
        let nutritionData = try encodeNutrition(nutrition)
        return CloudBackupSizeEstimate(
            profileByteCount: profileData.count,
            historyByteCount: historyData.count,
            historySessionCount: history.sessions.count,
            nutritionByteCount: nutritionData.count,
            nutritionMealCount: nutrition.recentMeals.count
        )
    }

    public func push(
        includeHistory: Bool,
        includeNutrition: Bool,
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
        }
        // When toggled off, keep the stale file -- do not delete.
        // Deletion is irreversible and silent. User can delete manually via Files if needed.

        var nutritionResult: CloudBackupNutritionPushResult?
        if includeNutrition {
            let nutrition = try buildNutritionBackup(now: now)
            let nutritionData = try encodeNutrition(nutrition)
            try fileStore.write(
                data: nutritionData,
                fileName: UbiquityCloudBackupFileStore.nutritionFileName
            )
            nutritionResult = CloudBackupNutritionPushResult(
                byteCount: nutritionData.count,
                recentCount: nutrition.recents.count,
                templateCount: nutrition.mealTemplates.count,
                mealCount: nutrition.recentMeals.count
            )
        }
        // When toggled off, keep the stale file -- do not delete.

        return CloudBackupPushResult(
            profileUpdatedAt: profile.updatedAt,
            profileByteCount: profileData.count,
            historyByteCount: historyByteCount,
            historySessionCount: historySessionCount,
            nutrition: nutritionResult
        )
    }

    /// Last-write-wins restore. Applies profile when cloud `updatedAt` is newer than
    /// `lastAppliedProfileUpdatedAt`, or when `forceIfFreshInstall` and local has no sessions.
    public func pullIfNeeded(
        includeHistory: Bool,
        includeNutrition: Bool,
        lastAppliedProfileUpdatedAt: Date?,
        forceIfFreshInstall: Bool,
        applyOnboardingCompleted: (Bool) -> Void,
        downloadTimeout: TimeInterval = iCloudDownloadTimeout
    ) throws -> CloudBackupPullResult {
        guard fileStore.isAvailable else { throw CloudBackupError.iCloudUnavailable }

        guard let profileData = try fileStore.read(
            fileName: UbiquityCloudBackupFileStore.profileFileName,
            downloadTimeout: downloadTimeout
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

        let historyResult = try importHistoryIfRequested(
            includeHistory: includeHistory,
            downloadTimeout: downloadTimeout
        )

        var nutritionImport: CloudBackupNutritionPullResult?
        if includeNutrition,
           let nutritionData = try fileStore.read(
               fileName: UbiquityCloudBackupFileStore.nutritionFileName,
               downloadTimeout: downloadTimeout
           ) {
            let backup = try decodeNutrition(nutritionData)
            nutritionImport = try applyNutrition(backup)
        }

        return CloudBackupPullResult(
            didRestoreProfile: shouldRestoreProfile,
            profileUpdatedAt: cloudProfile.updatedAt,
            historyRequested: historyResult.requested,
            historyFileFound: historyResult.fileFound,
            historyImport: historyResult.importResult,
            nutritionImport: nutritionImport
        )
    }

    /// Force restore regardless of LWW (manual "Restore from iCloud").
    public func pullForced(
        includeHistory: Bool,
        includeNutrition: Bool,
        applyOnboardingCompleted: (Bool) -> Void,
        downloadTimeout: TimeInterval = iCloudDownloadTimeout
    ) throws -> CloudBackupPullResult {
        guard fileStore.isAvailable else { throw CloudBackupError.iCloudUnavailable }

        guard let profileData = try fileStore.read(
            fileName: UbiquityCloudBackupFileStore.profileFileName,
            downloadTimeout: downloadTimeout
        ) else {
            throw CloudBackupError.missingProfileBackup
        }
        let cloudProfile = try decodeProfile(profileData)
        try applyProfile(cloudProfile, applyOnboardingCompleted: applyOnboardingCompleted)

        let historyResult = try importHistoryIfRequested(
            includeHistory: includeHistory,
            downloadTimeout: downloadTimeout
        )

        var nutritionImport: CloudBackupNutritionPullResult?
        if includeNutrition,
           let nutritionData = try fileStore.read(
               fileName: UbiquityCloudBackupFileStore.nutritionFileName,
               downloadTimeout: downloadTimeout
           ) {
            let backup = try decodeNutrition(nutritionData)
            nutritionImport = try applyNutrition(backup)
        }

        return CloudBackupPullResult(
            didRestoreProfile: true,
            profileUpdatedAt: cloudProfile.updatedAt,
            historyRequested: historyResult.requested,
            historyFileFound: historyResult.fileFound,
            historyImport: historyResult.importResult,
            nutritionImport: nutritionImport
        )
    }

    public func peekCloudHistorySummary(
        downloadTimeout: TimeInterval = iCloudDownloadTimeout
    ) throws -> CloudBackupCloudHistorySummary? {
        guard fileStore.isAvailable else { return nil }
        guard let historyData = try fileStore.read(
            fileName: UbiquityCloudBackupFileStore.historyFileName,
            downloadTimeout: downloadTimeout
        ) else {
            return nil
        }
        let export = try historyService.decode(historyData)
        return CloudBackupCloudHistorySummary(
            sessionCount: export.sessions.count,
            byteCount: historyData.count
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

    private struct HistoryImportAttempt: Sendable {
        let requested: Bool
        let fileFound: Bool
        let importResult: TrainingHistoryImportResult?
    }

    private func importHistoryIfRequested(
        includeHistory: Bool,
        downloadTimeout: TimeInterval
    ) throws -> HistoryImportAttempt {
        guard includeHistory else {
            return HistoryImportAttempt(requested: false, fileFound: false, importResult: nil)
        }
        guard let historyData = try fileStore.read(
            fileName: UbiquityCloudBackupFileStore.historyFileName,
            downloadTimeout: downloadTimeout
        ) else {
            return HistoryImportAttempt(requested: true, fileFound: false, importResult: nil)
        }
        let export = try historyService.decode(historyData)
        let importResult = try historyService.importHistory(export)
        return HistoryImportAttempt(requested: true, fileFound: true, importResult: importResult)
    }

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
        return sessions.isEmpty
    }

    // MARK: - Nutrition backup

    static let nutritionLookbackDays = 30

    func buildNutritionBackup(now: Date = Date()) throws -> HelmCloudNutritionBackup {
        let recents = try store.foodLog.fetchRecents(limit: 50)
        let templates = try store.mealTemplates.fetchAll()
        let calendar = Calendar.current
        let lookback = calendar.date(byAdding: .day, value: -Self.nutritionLookbackDays, to: now)!
        let startComponents = calendar.dateComponents([.year, .month, .day], from: lookback)
        let endComponents = calendar.dateComponents([.year, .month, .day], from: now)
        guard let startDay = HelmDay(components: startComponents),
              let endDay = HelmDay(components: endComponents) else {
            throw CloudBackupError.nutritionEncodingFailed
        }
        let meals = try store.nutrition.fetchMealsInRange(from: startDay, through: endDay)
        let recentMeals = try meals.map { meal in
            let lineItems = try store.foodLog.fetchLineItems(for: meal.id)
            return MealWithLineItems(meal: meal, lineItems: lineItems)
        }
        return HelmCloudNutritionBackup(
            updatedAt: now,
            recents: recents,
            mealTemplates: templates,
            recentMeals: recentMeals
        )
    }

    func encodeNutrition(_ backup: HelmCloudNutritionBackup) throws -> Data {
        do {
            return try fileEncoder.encode(backup)
        } catch {
            throw CloudBackupError.nutritionEncodingFailed
        }
    }

    func decodeNutrition(_ data: Data) throws -> HelmCloudNutritionBackup {
        do {
            let backup = try fileDecoder.decode(HelmCloudNutritionBackup.self, from: data)
            guard backup.schemaVersion <= HelmCloudNutritionBackup.currentSchemaVersion else {
                throw CloudBackupError.unsupportedNutritionSchemaVersion(backup.schemaVersion)
            }
            return backup
        } catch let error as CloudBackupError {
            throw error
        } catch {
            throw CloudBackupError.nutritionDecodingFailed
        }
    }

    func applyNutrition(_ backup: HelmCloudNutritionBackup) throws -> CloudBackupNutritionPullResult {
        let priorRecents = Set(try store.foodLog.fetchRecents(limit: 50).map { $0.ref })
        var importedRecentCount = 0
        for recent in backup.recents where !priorRecents.contains(recent.ref) {
            try store.foodLog.upsertRecent(recent)
            importedRecentCount += 1
        }

        let priorTemplates = try store.mealTemplates.fetchAll()
        let priorTemplateIDs = Set(priorTemplates.map { $0.id })
        var importedTemplateCount = 0
        for template in backup.mealTemplates where !priorTemplateIDs.contains(template.id) {
            try store.mealTemplates.save(template)
            importedTemplateCount += 1
        }

        var importedMealCount = 0
        for item in backup.recentMeals {
            if try store.nutrition.fetchMeal(id: item.meal.id) == nil {
                try store.nutrition.upsertMeal(item.meal)
                try store.foodLog.upsertLineItems(item.lineItems)
                importedMealCount += 1
            }
        }

        return CloudBackupNutritionPullResult(
            didImport: importedRecentCount > 0 || importedTemplateCount > 0 || importedMealCount > 0,
            recentCount: importedRecentCount,
            templateCount: importedTemplateCount,
            mealCount: importedMealCount
        )
    }
}
