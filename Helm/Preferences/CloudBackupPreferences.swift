import Foundation
import Observation

@MainActor
@Observable
final class CloudBackupPreferences {
    static let shared = CloudBackupPreferences()

    static let profileSyncEnabledKey = "helm.cloudBackup.profileSyncEnabled"
    static let historySyncEnabledKey = "helm.cloudBackup.historySyncEnabled"
    static let nutritionSyncEnabledKey = "helm.cloudBackup.nutritionSyncEnabled"
    static let lastPushedAtKey = "helm.cloudBackup.lastPushedAt"
    static let lastRestoredAtKey = "helm.cloudBackup.lastRestoredAt"
    static let lastAppliedProfileUpdatedAtKey = "helm.cloudBackup.lastAppliedProfileUpdatedAt"

    var profileSyncEnabled: Bool {
        didSet {
            guard !isHydrating else { return }
            defaults.set(profileSyncEnabled, forKey: Self.profileSyncEnabledKey)
            if !profileSyncEnabled {
                historySyncEnabled = false
                nutritionSyncEnabled = false
            }
        }
    }

    var historySyncEnabled: Bool {
        didSet {
            guard !isHydrating else { return }
            if historySyncEnabled, !profileSyncEnabled {
                historySyncEnabled = false
                return
            }
            defaults.set(historySyncEnabled, forKey: Self.historySyncEnabledKey)
        }
    }

    var nutritionSyncEnabled: Bool {
        didSet {
            guard !isHydrating else { return }
            if nutritionSyncEnabled, !profileSyncEnabled {
                nutritionSyncEnabled = false
                return
            }
            defaults.set(nutritionSyncEnabled, forKey: Self.nutritionSyncEnabledKey)
        }
    }

    private(set) var lastPushedAt: Date?
    private(set) var lastRestoredAt: Date?
    private(set) var lastAppliedProfileUpdatedAt: Date?

    private let defaults: UserDefaults
    private var isHydrating = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        profileSyncEnabled = defaults.bool(forKey: Self.profileSyncEnabledKey)
        historySyncEnabled = defaults.bool(forKey: Self.historySyncEnabledKey)
        nutritionSyncEnabled = defaults.bool(forKey: Self.nutritionSyncEnabledKey)
        lastPushedAt = defaults.object(forKey: Self.lastPushedAtKey) as? Date
        lastRestoredAt = defaults.object(forKey: Self.lastRestoredAtKey) as? Date
        lastAppliedProfileUpdatedAt = defaults.object(forKey: Self.lastAppliedProfileUpdatedAtKey) as? Date
        isHydrating = false
    }

    func recordPush(profileUpdatedAt: Date, at date: Date = Date()) {
        lastPushedAt = date
        defaults.set(date, forKey: Self.lastPushedAtKey)
        lastAppliedProfileUpdatedAt = profileUpdatedAt
        defaults.set(profileUpdatedAt, forKey: Self.lastAppliedProfileUpdatedAtKey)
    }

    func recordRestore(profileUpdatedAt: Date?, at date: Date = Date()) {
        lastRestoredAt = date
        defaults.set(date, forKey: Self.lastRestoredAtKey)
        if let profileUpdatedAt {
            lastAppliedProfileUpdatedAt = profileUpdatedAt
            defaults.set(profileUpdatedAt, forKey: Self.lastAppliedProfileUpdatedAtKey)
        }
    }
}
