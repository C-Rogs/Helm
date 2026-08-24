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

/// Codable backup of recent foods, meal templates, and recent meals.
public struct HelmCloudNutritionBackup: Codable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let updatedAt: Date
    public let recents: [FoodLogRecent]
    public let mealTemplates: [MealTemplate]
    public let recentMeals: [MealWithLineItems]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        updatedAt: Date = Date(),
        recents: [FoodLogRecent],
        mealTemplates: [MealTemplate],
        recentMeals: [MealWithLineItems]
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.recents = recents
        self.mealTemplates = mealTemplates
        self.recentMeals = recentMeals
    }
}

/// A logged meal with its line items for backup purposes.
public struct MealWithLineItems: Codable, Sendable, Hashable {
    public let meal: MealRecord
    public let lineItems: [MealLineItemRecord]

    public init(meal: MealRecord, lineItems: [MealLineItemRecord]) {
        self.meal = meal
        self.lineItems = lineItems
    }
}

public struct CloudBackupNutritionPushResult: Sendable, Hashable {
    public let byteCount: Int
    public let recentCount: Int
    public let templateCount: Int
    public let mealCount: Int

    public init(byteCount: Int, recentCount: Int, templateCount: Int, mealCount: Int) {
        self.byteCount = byteCount
        self.recentCount = recentCount
        self.templateCount = templateCount
        self.mealCount = mealCount
    }
}

public struct CloudBackupNutritionPullResult: Sendable, Hashable {
    public let didImport: Bool
    public let recentCount: Int
    public let templateCount: Int
    public let mealCount: Int

    public init(didImport: Bool, recentCount: Int, templateCount: Int, mealCount: Int) {
        self.didImport = didImport
        self.recentCount = recentCount
        self.templateCount = templateCount
        self.mealCount = mealCount
    }
}

public struct CloudBackupSizeEstimate: Sendable, Hashable {
    public let profileByteCount: Int
    public let historyByteCount: Int
    public let historySessionCount: Int
    public let nutritionByteCount: Int?
    public let nutritionMealCount: Int?

    public var profileByteCountFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(profileByteCount), countStyle: .file)
    }

    public var historyByteCountFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(historyByteCount), countStyle: .file)
    }

    public var nutritionByteCountFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(nutritionByteCount ?? 0), countStyle: .file)
    }

    public init(
        profileByteCount: Int,
        historyByteCount: Int,
        historySessionCount: Int,
        nutritionByteCount: Int? = nil,
        nutritionMealCount: Int? = nil
    ) {
        self.profileByteCount = profileByteCount
        self.historyByteCount = historyByteCount
        self.historySessionCount = historySessionCount
        self.nutritionByteCount = nutritionByteCount
        self.nutritionMealCount = nutritionMealCount
    }
}

public struct CloudBackupPushResult: Sendable, Hashable {
    public let profileUpdatedAt: Date
    public let profileByteCount: Int
    public let historyByteCount: Int?
    public let historySessionCount: Int?
    public let nutrition: CloudBackupNutritionPushResult?

    public init(
        profileUpdatedAt: Date,
        profileByteCount: Int,
        historyByteCount: Int?,
        historySessionCount: Int?,
        nutrition: CloudBackupNutritionPushResult? = nil
    ) {
        self.profileUpdatedAt = profileUpdatedAt
        self.profileByteCount = profileByteCount
        self.historyByteCount = historyByteCount
        self.historySessionCount = historySessionCount
        self.nutrition = nutrition
    }
}

public struct CloudBackupCloudHistorySummary: Sendable, Hashable {
    public let sessionCount: Int
    public let byteCount: Int

    public var byteCountFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    public init(sessionCount: Int, byteCount: Int) {
        self.sessionCount = sessionCount
        self.byteCount = byteCount
    }
}

public struct CloudBackupPullResult: Sendable, Hashable {
    public let didRestoreProfile: Bool
    public let profileUpdatedAt: Date?
    public let historyRequested: Bool
    public let historyFileFound: Bool
    public let historyImport: TrainingHistoryImportResult?
    public let nutritionImport: CloudBackupNutritionPullResult?

    public init(
        didRestoreProfile: Bool,
        profileUpdatedAt: Date?,
        historyRequested: Bool = false,
        historyFileFound: Bool = false,
        historyImport: TrainingHistoryImportResult?,
        nutritionImport: CloudBackupNutritionPullResult? = nil
    ) {
        self.didRestoreProfile = didRestoreProfile
        self.profileUpdatedAt = profileUpdatedAt
        self.historyRequested = historyRequested
        self.historyFileFound = historyFileFound
        self.historyImport = historyImport
        self.nutritionImport = nutritionImport
    }
}

public enum CloudBackupError: Error, Sendable, Equatable {
    case iCloudUnavailable
    case unsupportedProfileSchemaVersion(Int)
    case unsupportedNutritionSchemaVersion(Int)
    case profileDecodingFailed
    case profileEncodingFailed
    case nutritionDecodingFailed
    case nutritionEncodingFailed
    case missingProfileBackup
    case writeFailed(String)
    case readFailed(String)
    case downloadTimedOut(String)
}

extension CloudBackupError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "iCloud Drive is not available. Sign in to iCloud and enable iCloud Drive."
        case let .unsupportedProfileSchemaVersion(version):
            return "Unsupported cloud profile backup schema version \(version)."
        case let .unsupportedNutritionSchemaVersion(version):
            return "Unsupported cloud nutrition backup schema version \(version)."
        case .profileDecodingFailed:
            return "Could not read the iCloud profile backup."
        case .profileEncodingFailed:
            return "Could not encode the profile backup."
        case .nutritionDecodingFailed:
            return "Could not read the iCloud nutrition backup."
        case .nutritionEncodingFailed:
            return "Could not encode the nutrition backup."
        case .missingProfileBackup:
            return "No profile backup found in iCloud."
        case let .writeFailed(message):
            return "Failed to write iCloud backup: \(message)"
        case let .readFailed(message):
            return "Failed to read iCloud backup: \(message)"
        case let .downloadTimedOut(fileName):
            return "Timed out waiting for \(fileName) to download from iCloud. Stay on Wi‑Fi and try Restore again."
        }
    }
}
