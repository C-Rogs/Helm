import Core
import Foundation
import PatternKit
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("Pattern evaluation service")
struct PatternEvaluationServiceTests {
    @Test("evaluate retests a stored search spec")
    func retestsStoredSearchSpec() throws {
        let store = try PersistenceStore.inMemory()
        let spec = HypothesisSpec(
            id: "search_alcohol_present__resting_hr_lag1",
            exposure: ExposureSpec(field: .alcohol, op: .present),
            outcome: OutcomeSpec(field: .restingHr),
            lag: 1
        )
        try store.patternFindings.upsert(
            try PatternFindingCodec.stored(
                from: PatternFinding(
                    id: spec.id,
                    spec: spec,
                    status: .emerging,
                    verdict: .ship,
                    nExp: 14,
                    nCtrl: 20,
                    cliffsDelta: 0.2,
                    medianDelta: 4,
                    permutationP: 0.02,
                    fdrQ: 0.04,
                    ciLow: 0.05,
                    ciHigh: 0.4,
                    copyRegister: .tentative,
                    headline: "Starting to notice alcohol days and resting HR",
                    body: "n=14/20.",
                    firstDetectedAt: Date(),
                    updatedAt: Date()
                )
            )
        )
        let service = PatternEvaluationService(store: store)
        let findings = try service.evaluate(
            options: PatternEvaluationOptions(skipIfMatrixUnchanged: false)
        )
        #expect(findings.contains { $0.id == spec.id })
        let stored = try store.patternFindings.fetch(id: spec.id)
        #expect(stored != nil)
    }

    @Test("unchanged matrix skips a second catalog pass")
    func skipUnchangedMatrix() throws {
        let store = try PersistenceStore.inMemory()
        let service = PatternEvaluationService(store: store)
        _ = try service.evaluate(options: PatternEvaluationOptions(skipIfMatrixUnchanged: false))
        let firstUpdated = try store.patternFindings.fetchAll().map(\.updatedAt)
        _ = try service.evaluate()
        let secondUpdated = try store.patternFindings.fetchAll().map(\.updatedAt)
        #expect(firstUpdated == secondUpdated)
    }

    @Test("newly stable brief line is day-scoped")
    func newlyStableBrief() throws {
        let store = try PersistenceStore.inMemory()
        try store.appMetadata.setValue(
            "On low sleep duration, resting HR tends to run higher",
            forKey: PatternEvaluateMetadata.newlyStableHeadlineKey
        )
        try store.appMetadata.setValue("2026-01-15", forKey: PatternEvaluateMetadata.newlyStableDayKey)
        let service = PatternEvaluationService(store: store)
        let today = HelmDay(year: 2026, month: 1, day: 15)
        #expect(service.stableBriefLine(today: today)?.contains("low sleep") == true)
        #expect(service.stableBriefLine(today: HelmDay(year: 2026, month: 1, day: 16)) == nil)
    }

    @Test("card models sort stable before emerging before prior")
    func cardModelsSortByStatus() throws {
        let store = try PersistenceStore.inMemory()
        try upsertFinding(store: store, id: "prior", status: .priorSeed, copyRegister: .educational)
        try upsertFinding(store: store, id: "emerging", status: .emerging, copyRegister: .tentative)
        try upsertFinding(store: store, id: "stable", status: .stable, copyRegister: .confirmed)
        let cards = try PatternEvaluationService(store: store).cardModels()
        #expect(cards.map(\.id) == ["stable", "emerging", "prior"])
    }

    @Test("chat chip ignores literature priors")
    func narratableFindingsSkipPriors() throws {
        let store = try PersistenceStore.inMemory()
        try upsertFinding(store: store, id: "prior", status: .priorSeed, copyRegister: .educational)
        let service = PatternEvaluationService(store: store)
        #expect(try service.hasNarratableFindings() == false)
        try upsertFinding(store: store, id: "emerging", status: .emerging, copyRegister: .tentative)
        #expect(try service.hasNarratableFindings() == true)
    }

    private func upsertFinding(
        store: PersistenceStore,
        id: String,
        status: FindingStatus,
        copyRegister: CopyRegister
    ) throws {
        let spec = HypothesisSpec(
            id: id,
            exposure: ExposureSpec(field: .alcohol, op: .present),
            outcome: OutcomeSpec(field: .sleepAsleepMin),
            lag: 1
        )
        try store.patternFindings.upsert(
            try PatternFindingCodec.stored(
                from: PatternFinding(
                    id: id,
                    spec: spec,
                    status: status,
                    verdict: .ship,
                    nExp: 14,
                    nCtrl: 20,
                    cliffsDelta: 0.2,
                    medianDelta: -18,
                    permutationP: 0.02,
                    fdrQ: 0.04,
                    ciLow: 0.05,
                    ciHigh: 0.4,
                    copyRegister: copyRegister,
                    headline: id,
                    body: "n=14/20.",
                    firstDetectedAt: Date(),
                    updatedAt: Date()
                )
            )
        )
    }
}
