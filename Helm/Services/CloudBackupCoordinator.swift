import Foundation
import Observation
import Persistence

/// Coordinates opt-in iCloud Drive backups: estimate, push, pull, debounced hooks.
@MainActor
@Observable
final class CloudBackupCoordinator {
    static let shared = CloudBackupCoordinator()

    private static let debounceNanoseconds: UInt64 = 2_000_000_000

    private let persistence: PersistenceStore
    private let preferences: CloudBackupPreferences
    private let onboardingDefaults: UserDefaults
    private var service: CloudBackupService
    private var debounceTask: Task<Void, Never>?

    private(set) var sizeEstimate: CloudBackupSizeEstimate?
    private(set) var statusMessage: String?
    private(set) var errorMessage: String?
    private(set) var isBusy = false

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
        do {
            sizeEstimate = try service.estimateSizes(
                onboardingCompleted: onboardingCompleted
            )
            errorMessage = nil
        } catch {
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
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try service.push(
                includeHistory: preferences.historySyncEnabled,
                includeNutrition: preferences.nutritionSyncEnabled,
                onboardingCompleted: onboardingCompleted
            )
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
            let result = try service.pullIfNeeded(
                includeHistory: includeHistory,
                includeNutrition: includeNutrition,
                lastAppliedProfileUpdatedAt: preferences.lastAppliedProfileUpdatedAt,
                forceIfFreshInstall: true,
                applyOnboardingCompleted: applyOnboardingCompleted(_:)
            )
            if result.didRestoreProfile || result.historyImport != nil || result.nutritionImport != nil {
                preferences.recordRestore(profileUpdatedAt: result.profileUpdatedAt)
                if result.didRestoreProfile {
                    preferences.profileSyncEnabled = true
                    if result.historyImport != nil {
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
            return result.didRestoreProfile
        } catch CloudBackupError.missingProfileBackup {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func restoreForced() async -> Bool {
        isBusy = true
        defer { isBusy = false }
        do {
            let includeHistory = preferences.historySyncEnabled
                || (try? service.peekCloudProfileUpdatedAt()) != nil
            let includeNutrition = preferences.nutritionSyncEnabled
                || (try? service.peekCloudProfileUpdatedAt()) != nil
            let result = try service.pullForced(
                includeHistory: includeHistory,
                includeNutrition: includeNutrition,
                applyOnboardingCompleted: applyOnboardingCompleted(_:)
            )
            preferences.recordRestore(profileUpdatedAt: result.profileUpdatedAt)
            OnboardingStore.shared.syncFromDefaults()
            statusMessage = Self.describePull(result)
            errorMessage = nil
            refreshEstimate()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
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
        if let history = result.historyImport {
            parts.append(
                "Imported \(history.importedSessionCount) sessions (\(history.importedSetCount) sets)"
            )
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
