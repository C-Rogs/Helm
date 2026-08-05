import CoachLLM
import Core
import Foundation

/// Small profile / engine-config snapshot for iCloud Drive restore after reinstall.
public struct HelmCloudProfileBackup: Codable, Sendable, Hashable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let updatedAt: Date
    public let memoryProfile: MemoryProfile
    public let bodyProfile: BodyProfile?
    public let trainingPlanSettings: StoredTrainingPlanSettings
    /// Raw JSON from `plan_mesocycle_state` (avoids PlanKit dependency in Persistence).
    public let mesocycleStateJSON: String?
    public let onboardingCompleted: Bool

    public init(
        schemaVersion: Int = currentSchemaVersion,
        updatedAt: Date = Date(),
        memoryProfile: MemoryProfile,
        bodyProfile: BodyProfile?,
        trainingPlanSettings: StoredTrainingPlanSettings,
        mesocycleStateJSON: String?,
        onboardingCompleted: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.memoryProfile = memoryProfile
        self.bodyProfile = bodyProfile
        self.trainingPlanSettings = trainingPlanSettings
        self.mesocycleStateJSON = mesocycleStateJSON
        self.onboardingCompleted = onboardingCompleted
    }
}

public struct CloudBackupSizeEstimate: Sendable, Hashable {
    public let profileByteCount: Int
    public let historyByteCount: Int
    public let historySessionCount: Int

    public var profileByteCountFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(profileByteCount), countStyle: .file)
    }

    public var historyByteCountFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(historyByteCount), countStyle: .file)
    }

    public init(profileByteCount: Int, historyByteCount: Int, historySessionCount: Int) {
        self.profileByteCount = profileByteCount
        self.historyByteCount = historyByteCount
        self.historySessionCount = historySessionCount
    }
}

public struct CloudBackupPushResult: Sendable, Hashable {
    public let profileUpdatedAt: Date
    public let profileByteCount: Int
    public let historyByteCount: Int?
    public let historySessionCount: Int?

    public init(
        profileUpdatedAt: Date,
        profileByteCount: Int,
        historyByteCount: Int?,
        historySessionCount: Int?
    ) {
        self.profileUpdatedAt = profileUpdatedAt
        self.profileByteCount = profileByteCount
        self.historyByteCount = historyByteCount
        self.historySessionCount = historySessionCount
    }
}

public struct CloudBackupPullResult: Sendable, Hashable {
    public let didRestoreProfile: Bool
    public let profileUpdatedAt: Date?
    public let historyImport: TrainingHistoryImportResult?

    public init(
        didRestoreProfile: Bool,
        profileUpdatedAt: Date?,
        historyImport: TrainingHistoryImportResult?
    ) {
        self.didRestoreProfile = didRestoreProfile
        self.profileUpdatedAt = profileUpdatedAt
        self.historyImport = historyImport
    }
}

public enum CloudBackupError: Error, Sendable, Equatable {
    case iCloudUnavailable
    case unsupportedProfileSchemaVersion(Int)
    case profileDecodingFailed
    case profileEncodingFailed
    case missingProfileBackup
    case writeFailed(String)
    case readFailed(String)
}

extension CloudBackupError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "iCloud Drive is not available. Sign in to iCloud and enable iCloud Drive."
        case let .unsupportedProfileSchemaVersion(version):
            return "Unsupported cloud profile backup schema version \(version)."
        case .profileDecodingFailed:
            return "Could not read the iCloud profile backup."
        case .profileEncodingFailed:
            return "Could not encode the profile backup."
        case .missingProfileBackup:
            return "No profile backup found in iCloud."
        case let .writeFailed(message):
            return "Failed to write iCloud backup: \(message)"
        case let .readFailed(message):
            return "Failed to read iCloud backup: \(message)"
        }
    }
}
