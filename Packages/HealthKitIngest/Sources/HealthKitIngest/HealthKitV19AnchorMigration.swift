import Foundation

/// One-shot reset of v19 HealthKit query anchors. Completes only after every kind succeeds
/// so a failed persist can retry on the next launch.
public enum HealthKitV19AnchorMigration: Sendable {
    public static let defaultsKey = "did-reset-v19-healthkit-anchors"
    public static let kinds: [HealthKitSampleKind] = [
        .bodyFatPercentage,
        .stepCount,
        .basalEnergy
    ]

    public static func runIfNeeded(
        defaults: UserDefaults = .standard,
        reset: (HealthKitSampleKind) async throws -> Void
    ) async throws {
        guard !defaults.bool(forKey: defaultsKey) else { return }
        for kind in kinds {
            try await reset(kind)
        }
        defaults.set(true, forKey: defaultsKey)
    }
}
