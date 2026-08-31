import Foundation

/// One-shot reset of the body-fat HealthKit query anchor after percent-unit ingest
/// started accepting whole-number samples. Completes only after reset succeeds so a
/// failed persist can retry on the next launch.
public enum HealthKitV20AnchorMigration: Sendable {
    public static let defaultsKey = "did-reset-v20-healthkit-anchors"
    public static let kinds: [HealthKitSampleKind] = [
        .bodyFatPercentage
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
