import CoachLLM
import Core
import Foundation
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("Coach mutation idempotency")
struct CoachMutationIdempotencyTests {
    @Test("ledger records and detects applied keys")
    func ledgerRoundTrip() throws {
        let store = try PersistenceStore.inMemory()
        let ledger = CoachMutationLedger(metadata: store.appMetadata)
        let key = "food_log|delete|2026-09-07|dinner|\(UUID().uuidString)|0:"
        #expect(!ledger.wasApplied(key))
        try ledger.recordApplied(key)
        #expect(ledger.wasApplied(key))
    }

    @Test("meal copy key is stable for same command")
    func mealCopyKeyStable() {
        let command = HelmCopyMealCommand(
            sourceDay: HelmDay(year: 2026, month: 9, day: 7),
            sourceBucket: .dinner,
            targetDay: HelmDay(year: 2026, month: 9, day: 9),
            targetBucket: .dinner
        )
        let first = CoachMutationIdempotency.key(forMealCopy: command)
        let second = CoachMutationIdempotency.key(forMealCopy: command)
        #expect(first == second)
    }
}
