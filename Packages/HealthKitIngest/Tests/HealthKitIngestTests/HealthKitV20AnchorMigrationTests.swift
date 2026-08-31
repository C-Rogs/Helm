import Foundation
import Testing
@testable import HealthKitIngest

@Suite("HealthKit v20 anchor migration")
struct HealthKitV20AnchorMigrationTests {
    @Test("success marks the one-shot complete")
    func successMarksComplete() async throws {
        let defaults = try isolatedDefaults()
        var reset: [HealthKitSampleKind] = []
        try await HealthKitV20AnchorMigration.runIfNeeded(defaults: defaults) { kind in
            reset.append(kind)
        }
        #expect(reset == HealthKitV20AnchorMigration.kinds)
        #expect(defaults.bool(forKey: HealthKitV20AnchorMigration.defaultsKey))
    }

    @Test("failed reset leaves the one-shot incomplete")
    func failureDoesNotMarkComplete() async throws {
        let defaults = try isolatedDefaults()
        await #expect(throws: HealthKitIngestError.self) {
            try await HealthKitV20AnchorMigration.runIfNeeded(defaults: defaults) { _ in
                throw HealthKitIngestError.anchorPersistenceFailed("disk")
            }
        }
        #expect(!defaults.bool(forKey: HealthKitV20AnchorMigration.defaultsKey))
    }

    @Test("already complete skips reset")
    func alreadyCompleteSkipsReset() async throws {
        let defaults = try isolatedDefaults()
        defaults.set(true, forKey: HealthKitV20AnchorMigration.defaultsKey)
        var resetCount = 0
        try await HealthKitV20AnchorMigration.runIfNeeded(defaults: defaults) { _ in
            resetCount += 1
        }
        #expect(resetCount == 0)
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let suite = "helm-v20-anchor-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
