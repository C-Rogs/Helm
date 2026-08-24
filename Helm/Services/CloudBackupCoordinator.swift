import Foundation
import Observation
import Persistence

/// Coordinates opt-in iCloud Drive backups: estimate, push, pull, debounced hooks.
@MainActor
@Observable
final class CloudBackupCoordinator {
    static let shared = CloudBackupCoordinator()

    private static let debounceNanoseconds: UInt64 = 2_000_000_000
    private static let historyRetryDelays: [UInt64] = [15_000_000_000, 45_000_000_000]

    private let persistence: PersistenceStore
    private let preferences: CloudBackupPreferences
    private let onboardingDefaults: UserDefaults
    private let service: CloudBackupService
    private var debounceTask: Task<Void, Never>?
    private var historyRetryTask: Task<Void, Never>?

    private(set) var sizeEstimate: CloudBackupSizeEstimate?
    private(set) var cloudHistorySummary: CloudBackupCloudHistorySummary?
    private(set) var cloudHistoryStatusMessage: String?
    private(set) var statusMessage: String?
    private(set) var errorMessage: String?
    private(set) var isBusy = false
    private var isEstimating = false

    var isAvailable: Bool { service.isAvailable }

    init(
        persistence: PersistenceStore = PersistenceBootstrap.persistenceStore,
        preferences: CloudBackupPreferences = .shared,
        fileStore: (any CloudBackupFileStore)? = nil,
        onboardingDefaults: UserDefaults = .standard
    ) {
        self.persistence = persistence
        self.preferences = preferences
        self.onboardingDefaults = onboardingDefaults
        service = CloudBackupService(
            store: persistence,
            fileStore: fileStore ?? UbiquityCloudBackupFileStore()
        )
    }

    func refreshEstimate() {
        guard !isEstimating else { return }
        isEstimating = true
        let service = service
        let onboardingCompleted = onboardingCompleted
        Task { [weak self] in
            let estimate = await Result<CloudBackupSizeEstimate, Error> {
                try service.estimateSizes(onboardingCompleted: onboardingCompleted)
            }
            guard let self else { return }
            switch estimate {
            case .success(let value):
                sizeEstimate = value
                errorMessage = nil
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
            isEstimating = false
        }
    }

    func refreshCloudStatus() async {
        guard service.isAvailable else {
            cloudHistorySummary = nil
            cloudHistoryStatusMessage = "iCloud Drive unavailable"
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let pullService = service
            let summary = try await Task.detached(priority: .utility) {
                try pullService.peekCloudHistorySummary()
            }.value
            cloudHistorySummary = summary
            cloudHistoryStatusMessage = summary.map {
                "\($0.byteCountFormatted) · \($0.sessionCount) sessions in iCloud"
            } ?? "No workout history file in iCloud"
            errorMessage = nil
        } catch {
            cloudHistorySummary = nil
            cloudHistoryStatusMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    func schedulePush() {
        guard preferences.profileSyncEnabled else { return }
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.debounceNanoseconds)
            guard !Task.isCancelled else { return }
            await pushNow(reason: "auto")
        }
    }

    @discardableResult
    func pushNow(reason: String = "manual") async -> Bool {
        guard preferences.profileSyncEnabled else {
            errorMessage = "Turn on profile sync first."
            return false
        }
        statusMessage = "Backing up…"
        isBusy = true
        defer { isBusy = false }
        do {
            let pushService = service
            let includeHistory = preferences.historySyncEnabled
            let includeNutrition = preferences.nutritionSyncEnabled
            let completed = onboardingCompleted
            let result = try await runPushOnBackground {
                try pushService.push(
                    includeHistory: includeHistory,
                    includeNutrition: includeNutrition,
                    onboardingCompleted: completed
                )
            }
            preferences.recordPush(profileUpdatedAt: result.profileUpdatedAt)
            var parts = [
                "Backed up profile (\(ByteCountFormatter.string(fromByteCount: Int64(result.profileByteCount), countStyle: .file)))"
            ]
            if let historyBytes = result.historyByteCount,
               let sessions = result.historySessionCount {
                parts.append(
                    "history \(sessions) sessions (\(ByteCountFormatter.string(fromByteCount: Int64(historyBytes), countStyle: .file)))"
                )
            }
            if let nutrition = result.nutrition {
                parts.append(
                    "nutrition \(nutrition.mealCount) meals (\(ByteCountFormatter.string(fromByteCount: Int64(nutrition.byteCount), countStyle: .file)))"
                )
            }
            statusMessage = parts.joined(separator: " · ")
            errorMessage = nil
            refreshEstimate()
            await refreshCloudStatus()
            _ = reason
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Launch path: restore when sync enabled, or when local is empty and iCloud has a backup
    /// (UserDefaults toggles are wiped on app delete).
    @discardableResult
    func pullIfNeededOnLaunch() async -> Bool {
        let restored = await performPullIfNeeded()
        if shouldRetryHistoryDownload() {
            scheduleHistoryDownloadRetries()
        }
        return restored
    }

    @discardableResult
    func restoreForced() async -> Bool {
        statusMessage = "Restoring…"
        isBusy = true
        defer { isBusy = false }
        do {
            let includeHistory = preferences.historySyncEnabled
                || (try? service.peekCloudProfileUpdatedAt()) != nil
            let includeNutrition = preferences.nutritionSyncEnabled
                || (try? service.peekCloudProfileUpdatedAt()) != nil
            let onboardingBox = OnboardingCaptureBox()
            let pullService = service
            let result = try await runPullOnBackground {
                try pullService.pullForced(
                    includeHistory: includeHistory,
                    includeNutrition: includeNutrition,
                    applyOnboardingCompleted: onboardingBox.capture
                )
            }
            if let completed = onboardingBox.value {
                applyOnboardingCompleted(completed)
            }
            preferences.recordRestore(profileUpdatedAt: result.profileUpdatedAt)
            OnboardingStore.shared.syncFromDefaults()
            statusMessage = Self.describePull(result)
            errorMessage = nil
            refreshEstimate()
            await refreshCloudStatus()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func performPullIfNeeded() async -> Bool {
        guard service.isAvailable else { return false }

        let cloudUpdatedAt = try? service.peekCloudProfileUpdatedAt()
        guard cloudUpdatedAt != nil else { return false }

        let shouldAttempt =
            preferences.profileSyncEnabled
            || preferences.lastAppliedProfileUpdatedAt == nil
        guard shouldAttempt else { return false }

        isBusy = true
        defer { isBusy = false }
        do {
            // After delete, prefs are gone; try history + nutrition files (no-op if missing).
            let includeHistory = preferences.historySyncEnabled || !preferences.profileSyncEnabled
            let includeNutrition = preferences.nutritionSyncEnabled || !preferences.profileSyncEnabled
            let onboardingBox = OnboardingCaptureBox()
            let pullService = service
            let lastAppliedProfileUpdatedAt = preferences.lastAppliedProfileUpdatedAt
            let result = try await runPullOnBackground {
                try pullService.pullIfNeeded(
                    includeHistory: includeHistory,
                    includeNutrition: includeNutrition,
                    lastAppliedProfileUpdatedAt: lastAppliedProfileUpdatedAt,
                    forceIfFreshInstall: true,
                    applyOnboardingCompleted: onboardingBox.capture
                )
            }
            if let completed = onboardingBox.value {
                applyOnboardingCompleted(completed)
            }
            if result.didRestoreProfile || result.historyImport != nil || result.nutritionImport != nil {
                preferences.recordRestore(profileUpdatedAt: result.profileUpdatedAt)
                if result.didRestoreProfile {
                    preferences.profileSyncEnabled = true
                    if result.historyFileFound {
                        preferences.historySyncEnabled = true
                    }
                    if result.nutritionImport?.didImport == true {
                        preferences.nutritionSyncEnabled = true
                    }
                }
                OnboardingStore.shared.syncFromDefaults()
                statusMessage = Self.describePull(result)
            }
            errorMessage = nil
            await refreshCloudStatus()
            return result.didRestoreProfile
        } catch CloudBackupError.missingProfileBackup {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func shouldRetryHistoryDownload() -> Bool {
        guard service.isAvailable else { return false }
        guard cloudHistorySummary == nil else { return false }
        guard (try? service.peekCloudProfileUpdatedAt()) != nil else { return false }
        guard preferences.historySyncEnabled || preferences.lastAppliedProfileUpdatedAt == nil else { return false }
        return true
    }

    private func scheduleHistoryDownloadRetries() {
        historyRetryTask?.cancel()
        historyRetryTask = Task { @MainActor in
            for delay in Self.historyRetryDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                await refreshCloudStatus()
                guard cloudHistorySummary == nil else { return }
                _ = await performPullIfNeeded()
            }
        }
    }

    private func runPushOnBackground(
        _ work: @escaping @Sendable () throws -> CloudBackupPushResult
    ) async throws -> CloudBackupPushResult {
        try await Task.detached(priority: .userInitiated, operation: work).value
    }

    private func runPullOnBackground(
        _ work: @escaping @Sendable () throws -> CloudBackupPullResult
    ) async throws -> CloudBackupPullResult {
        try await Task.detached(priority: .userInitiated, operation: work).value
    }

    private var onboardingCompleted: Bool {
        onboardingDefaults.bool(forKey: OnboardingStore.completedDefaultsKey)
    }

    private func applyOnboardingCompleted(_ completed: Bool) {
        onboardingDefaults.set(completed, forKey: OnboardingStore.completedDefaultsKey)
    }

    private static func describePull(_ result: CloudBackupPullResult) -> String {
        var parts: [String] = []
        if result.didRestoreProfile {
            parts.append("Restored profile & engine config")
        }
        if result.historyRequested {
            if let history = result.historyImport {
                if history.importedSessionCount > 0 {
                    parts.append(
                        "Imported \(history.importedSessionCount) sessions (\(history.importedSetCount) sets)"
                    )
                } else if history.skippedDuplicateCount > 0 {
                    parts.append(
                        "All \(history.skippedDuplicateCount) sessions already on this device"
                    )
                } else {
                    parts.append("Workout history file was empty")
                }
            } else if !result.historyFileFound {
                parts.append(
                    "Workout history not found in iCloud. Turn on Include workout history, tap Back Up Now on your old device, or export Training History JSON."
                )
            }
        }
        if let nutrition = result.nutritionImport, nutrition.didImport {
            var nutritionParts: [String] = []
            if nutrition.recentCount > 0 { nutritionParts.append("\(nutrition.recentCount) foods") }
            if nutrition.templateCount > 0 { nutritionParts.append("\(nutrition.templateCount) templates") }
            if nutrition.mealCount > 0 { nutritionParts.append("\(nutrition.mealCount) meals") }
            if !nutritionParts.isEmpty {
                parts.append("Nutrition: \(nutritionParts.joined(separator: ", "))")
            }
        }
        if parts.isEmpty {
            return "iCloud backup already up to date"
        }
        return parts.joined(separator: " · ")
    }
}

private final class OnboardingCaptureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Bool?

    var value: Bool? {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func capture(_ completed: Bool) {
        lock.lock()
        _value = completed
        lock.unlock()
    }
}
