import Core
import Foundation
import Persistence
import PlanKit
import ReadinessKit
import Testing
@testable import HealthKitIngest

@Suite("Prescription service")
struct PrescriptionServiceTests {
    @Test("phase change re-plans total volume")
    func phaseChangeReplans() async throws {
        let store = try PersistenceStore.inMemory()
        try seedCatalog(in: store)

        let engine = PlanPrescriptionEngine(persistence: store)
        let day = HelmDay(year: 2026, month: 7, day: 23)

        try store.trainingPlan.save(StoredTrainingPlanSettings(phaseGoal: PhaseGoal(phase: .cut)))
        let cut = try await engine.computeSession(for: day, readiness: nil)

        try store.trainingPlan.save(StoredTrainingPlanSettings(phaseGoal: PhaseGoal(phase: .gain)))
        let gain = try await engine.computeSession(for: day, readiness: nil)

        let cutSets = cut.exercises.reduce(0) { $0 + $1.targetSets }
        let gainSets = gain.exercises.reduce(0) { $0 + $1.targetSets }
        #expect(cutSets < gainSets)
    }

    @Test("dashboard summary renders exercise rows")
    func dashboardSummary() async throws {
        let store = try PersistenceStore.inMemory()
        try seedCatalog(in: store)
        try store.trainingPlan.save(.default)

        let engine = PlanPrescriptionEngine(persistence: store)
        let day = HelmDay(year: 2026, month: 7, day: 23)
        let state = try await engine.dashboardState(for: day, readiness: nil)

        guard case let .prescribed(summary) = state else {
            Issue.record("Expected prescribed state")
            return
        }

        #expect(!summary.exercises.isEmpty)
        #expect(summary.totalSets > 0)
        #expect(summary.phase == .maintain)
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
