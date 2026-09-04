import CoachLLM
import Core
import Foundation
import PatternKit
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("Pattern query service")
struct PatternQueryServiceTests {
    @Test("returns stored cards only and filters by field")
    func filtersStoredCards() throws {
        let store = try PersistenceStore.inMemory()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try store.patternFindings.upsert(
            try storedFinding(
                id: "alcohol_worse_sleep",
                spec: SeedCatalog.all.first { $0.id == "alcohol_worse_sleep" }!,
                status: .emerging,
                headline: "Starting to notice alcohol days and sleep duration",
                body: "n=14/22.",
                now: now
            )
        )
        try store.patternFindings.upsert(
            try storedFinding(
                id: "office_volume_residual",
                spec: SeedCatalog.all.first { $0.id == "office_volume_residual" }!,
                status: .stable,
                headline: "On office days, volume vs prescription tends to shift",
                body: "n=32/40.",
                now: now
            )
        )

        let service = PatternQueryService(store: store)
        let alcohol = try service.run(PatternQueryPayload(status: .all, field: "alcohol"))
        #expect(alcohol.contains("alcohol_worse_sleep"))
        #expect(!alcohol.contains("office_volume_residual"))

        let none = try service.run(PatternQueryPayload(status: .retired))
        #expect(none.contains("findings=none"))
    }

    @Test("confirm to memory appends nutrition line")
    func confirmToMemory() throws {
        let store = try PersistenceStore.inMemory()
        let spec = SeedCatalog.all.first { $0.id == "alcohol_worse_sleep" }!
        try store.patternFindings.upsert(
            try storedFinding(
                id: spec.id,
                spec: spec,
                status: .stable,
                headline: "On alcohol days, sleep duration tends to shift",
                body: "n=32/40.",
                now: Date()
            )
        )
        let service = PatternEvaluationService(store: store)
        try service.confirmToMemory(id: spec.id)
        let profile = try store.memoryProfile.load()
        #expect(profile.nutritionPatterns.contains("On alcohol days, sleep duration tends to shift"))
        let stored = try #require(try store.patternFindings.fetch(id: spec.id))
        #expect(stored.status == "memory_confirmed")
    }

    @Test("short field needle does not fuzzy-match resting_hr")
    func shortFieldNeedle() throws {
        let store = try PersistenceStore.inMemory()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let spec = HypothesisSpec(
            id: "low_sleep_higher_rhr",
            exposure: ExposureSpec(field: .sleepAsleepMin, op: .tertileLow),
            outcome: OutcomeSpec(field: .restingHr),
            lag: 1
        )
        try store.patternFindings.upsert(
            try storedFinding(
                id: spec.id,
                spec: spec,
                status: .stable,
                headline: "On low sleep duration, resting HR tends to run higher",
                body: "n=32/40.",
                now: now
            )
        )
        let service = PatternQueryService(store: store)
        let short = try service.run(PatternQueryPayload(status: .all, field: "hr"))
        #expect(short.contains("findings=none"))
        let exact = try service.run(PatternQueryPayload(status: .all, field: "resting_hr"))
        #expect(exact.contains("low_sleep_higher_rhr"))
    }
}

private func storedFinding(
    id: String,
    spec: HypothesisSpec,
    status: FindingStatus,
    headline: String,
    body: String,
    now: Date
) throws -> StoredPatternFinding {
    let finding = PatternFinding(
        id: id,
        spec: spec,
        status: status,
        verdict: .ship,
        nExp: 20,
        nCtrl: 20,
        cliffsDelta: 0.3,
        medianDelta: -12,
        permutationP: 0.01,
        fdrQ: 0.04,
        ciLow: 0.1,
        ciHigh: 0.5,
        copyRegister: .tentative,
        headline: headline,
        body: body,
        firstDetectedAt: now,
        updatedAt: now
    )
    return try PatternFindingCodec.stored(from: finding)
}
