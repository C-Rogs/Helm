import CoachLLM
import Core
import Foundation
import Persistence
import ReadinessKit
import Testing
@testable import HealthKitIngest

@Suite("Brief engine")
struct BriefEngineTests {
    @Test("engine-only brief renders from fixture inputs")
    func engineOnlyBrief() async throws {
        let store = try PersistenceStore.inMemory()
        try seedCatalog(in: store)
        try store.trainingPlan.save(.default)

        let engine = BriefEngine(
            persistence: store,
            prescriptionEngine: PlanPrescriptionEngine(persistence: store),
            narrator: MorningBriefNarrator { _ in nil }
        )

        let day = HelmDay(year: 2026, month: 7, day: 23)
        let readiness = readinessScore(score: 72, band: .balanced)

        let prescriptionEngine = PlanPrescriptionEngine(persistence: store)
        let summary = try await prescriptionEngine.dashboardState(for: day, readiness: readiness)
        guard case let .prescribed(prescribedSummary) = summary else {
            Issue.record("Expected prescribed summary")
            return
        }

        let brief = try await engine.ensureBrief(
            for: day,
            readiness: readiness,
            prescriptionSummary: prescribedSummary,
            attemptNarration: false
        )

        #expect(brief.source == .engineOnly)
        #expect(!brief.engineText.contains("ARC 72"))
        #expect(brief.engineText.contains("sets"))
        #expect(brief.engineText.contains("kcal"))
        #expect(brief.engineText.contains("protein"))
    }

    @Test("brief regenerates only when inputs change")
    func fingerprintCache() async throws {
        let store = try PersistenceStore.inMemory()
        try seedCatalog(in: store)
        try store.trainingPlan.save(.default)

        let narrationCounter = LockedCounter()
        let narrator = MorningBriefNarrator { _ in
            narrationCounter.increment()
            return CoachStructuredArtefact(
                payload: MorningBriefPayload(
                    schemaVersion: CoachOutputSchemaVersion.briefV1.rawValue,
                    narration: "Coach narration.",
                    citationIDs: ["ev-chest-1"]
                ),
                schemaVersion: .briefV1,
                promptVersion: .briefV1
            )
        }

        let prescriptionEngine = PlanPrescriptionEngine(persistence: store)
        let engine = BriefEngine(
            persistence: store,
            prescriptionEngine: prescriptionEngine,
            narrator: narrator
        )

        let day = HelmDay(year: 2026, month: 7, day: 23)
        let readiness = readinessScore(score: 60, band: .balanced)
        let summary = try await prescriptionEngine.dashboardState(for: day, readiness: readiness)
        guard case let .prescribed(prescribedSummary) = summary else {
            Issue.record("Expected prescribed summary")
            return
        }

        let first = try await engine.ensureBrief(
            for: day,
            readiness: readiness,
            prescriptionSummary: prescribedSummary,
            attemptNarration: true
        )
        #expect(first.source == .coach)
        #expect(narrationCounter.value == 1)

        let cached = try await engine.ensureBrief(
            for: day,
            readiness: readiness,
            prescriptionSummary: prescribedSummary,
            attemptNarration: true
        )
        #expect(cached == first)
        #expect(narrationCounter.value == 1)

        let depleted = readinessScore(score: 28, band: .depleted)
        let adjustedSummary = try await prescriptionEngine.dashboardState(for: day, readiness: depleted)
        guard case let .prescribed(adjusted) = adjustedSummary else {
            Issue.record("Expected prescribed summary")
            return
        }

        let refreshed = try await engine.ensureBrief(
            for: day,
            readiness: depleted,
            prescriptionSummary: adjusted,
            attemptNarration: true
        )
        #expect(refreshed.inputFingerprint != first.inputFingerprint)
        #expect(narrationCounter.value == 2)
    }

    @Test("offline narrator keeps engine-only brief")
    func offlineFallback() async throws {
        let store = try PersistenceStore.inMemory()
        try seedCatalog(in: store)
        try store.trainingPlan.save(.default)

        let engine = BriefEngine(
            persistence: store,
            prescriptionEngine: PlanPrescriptionEngine(persistence: store),
            narrator: MorningBriefNarrator { _ in nil }
        )

        let day = HelmDay(year: 2026, month: 7, day: 23)
        let brief = try await engine.ensureBrief(
            for: day,
            readiness: nil,
            prescriptionSummary: nil,
            attemptNarration: true
        )

        #expect(brief.source == .engineOnly)
        #expect(brief.displayText == brief.engineText)
        #expect(brief.citationIDs.isEmpty)
    }

    private func readinessScore(score: Int, band: ReadinessBand) -> ReadinessScore {
        ReadinessScore(
            score: score,
            band: band,
            confidence: .high,
            confidenceValue: 0.9,
            hrvBand: .typical,
            validNights: 14,
            stabilityScore: 0.8,
            contributors: ReadinessContributorBreakdown(
                zHRV: 0.2,
                zRestingHR: 0.0,
                zSleep: 0.1,
                zRespiratory: nil,
                zTemperature: nil,
                zStrain: nil,
                zComposite: 0.2,
                rawScore: Double(score),
                dampedScore: Double(score)
            ),
            effectiveHRVMilliseconds: 50,
            restingHeartRate: 55
        )
    }

    private func seedCatalog(in store: PersistenceStore) throws {
        try store.exercises.upsert(
            id: "bench_press",
            canonicalName: "Bench Press",
            displayName: "Bench Press",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "chest",
            isPickerDefault: true
        )
        try store.exercises.upsert(
            id: "squat",
            canonicalName: "Squat",
            displayName: "Squat",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "quadriceps",
            isPickerDefault: true
        )
        try store.exercises.upsert(
            id: "lat_pulldown",
            canonicalName: "Lat Pulldown",
            displayName: "Lat Pulldown",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "lats",
            isPickerDefault: true
        )
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}
