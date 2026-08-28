import Foundation
import Testing
@testable import HealthKitIngest

@Suite("HealthKit v19 anchor migration")
struct HealthKitV19AnchorMigrationTests {
    @Test("success marks the one-shot complete")
    func successMarksComplete() async throws {
        let defaults = try isolatedDefaults()
        var reset: [HealthKitSampleKind] = []
        try await HealthKitV19AnchorMigration.runIfNeeded(defaults: defaults) { kind in
            reset.append(kind)
        }
        #expect(reset == HealthKitV19AnchorMigration.kinds)
        #expect(defaults.bool(forKey: HealthKitV19AnchorMigration.defaultsKey))
    }

    @Test("failed reset leaves the one-shot incomplete")
    func failureDoesNotMarkComplete() async throws {
        let defaults = try isolatedDefaults()
        var reset: [HealthKitSampleKind] = []
        await #expect(throws: HealthKitIngestError.self) {
            try await HealthKitV19AnchorMigration.runIfNeeded(defaults: defaults) { kind in
                reset.append(kind)
                if kind == .stepCount {
                    throw HealthKitIngestError.anchorPersistenceFailed("disk")
                }
            }
        }
        #expect(reset == [.bodyFatPercentage, .stepCount])
        #expect(!defaults.bool(forKey: HealthKitV19AnchorMigration.defaultsKey))
    }

    @Test("already complete skips reset")
    func alreadyCompleteSkipsReset() async throws {
        let defaults = try isolatedDefaults()
        defaults.set(true, forKey: HealthKitV19AnchorMigration.defaultsKey)
        var resetCount = 0
        try await HealthKitV19AnchorMigration.runIfNeeded(defaults: defaults) { _ in
            resetCount += 1
        }
        #expect(resetCount == 0)
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let suite = "helm-v19-anchor-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
