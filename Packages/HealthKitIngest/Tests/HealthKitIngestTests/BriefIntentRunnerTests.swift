import Core
import Diagnostics
import Foundation
import HealthKitIngest
import Persistence
import ReadinessKit
import Testing

@Suite("Brief intent runner")
struct BriefIntentRunnerTests {
    @Test("Locked phone records miss and skips pipeline")
    func lockedPhoneRecordsMiss() async throws {
        let store = try PersistenceStore.inMemory()
        try seedCatalog(in: store)
        try store.trainingPlan.save(.default)

        let runner = makeRunner(
            store: store,
            protectedData: FixedProtectedDataChecker(isAvailable: false),
            notificationPoster: RecordingBriefNotificationPoster()
        )

        let day = HelmDay(year: 2026, month: 7, day: 23)
        let outcome = await runner.run(
            now: day.startInstant(calendar: Calendar(identifier: .gregorian)) ?? .now,
            attemptNarration: false
        )

        #expect(outcome == .lockedPhone)

        let missStore = BriefIntentMissStore(metadata: store.appMetadata)
        #expect(try missStore.hasPendingMiss(for: day))
    }

    @Test("Unlocked phone generates brief and posts notification")
    func unlockedPipelinePostsNotification() async throws {
        let store = try PersistenceStore.inMemory()
        try seedCatalog(in: store)
        try store.trainingPlan.save(.default)

        let poster = RecordingBriefNotificationPoster()
        let runner = makeRunner(
            store: store,
            protectedData: FixedProtectedDataChecker(isAvailable: true),
            notificationPoster: poster
        )

        let day = HelmDay(year: 2026, month: 7, day: 23)
        let outcome = await runner.run(
            now: day.startInstant(calendar: Calendar(identifier: .gregorian)) ?? .now,
            attemptNarration: false
        )

        #expect(outcome == .succeeded(notificationPosted: true))
        #expect(poster.postedBrief != nil)
        #expect(try store.brief.fetch(for: day) != nil)

        let missStore = BriefIntentMissStore(metadata: store.appMetadata)
        #expect(try missStore.pendingMissDay() == nil)
    }

    @Test("Brief notification planner truncates long copy")
    func notificationBodyTruncation() {
        let longText = String(repeating: "a", count: 220)
        let brief = StoredDailyBrief(
            helmDay: HelmDay(year: 2026, month: 7, day: 23),
            inputFingerprint: "fp",
            engineText: longText,
            narrationText: longText,
            citationIDs: [],
            source: .engineOnly,
            promptVersion: nil,
            schemaVersion: nil,
            updatedAt: .now
        )

        let body = BriefNotificationPlanner.body(for: brief)
        #expect(body.count == 180)
        #expect(body.hasSuffix("..."))
    }

    private func makeRunner(
        store: PersistenceStore,
        protectedData: FixedProtectedDataChecker,
        notificationPoster: RecordingBriefNotificationPoster
    ) -> BriefIntentRunner {
        BriefIntentRunner(
            ingest: HealthKitIngest(
                persistence: store,
                anchorDirectoryURL: FileManager.default.temporaryDirectory
            ),
            readinessEngine: ReadinessEngine(persistence: store),
            prescriptionEngine: PlanPrescriptionEngine(persistence: store),
            briefEngine: BriefEngine(
                persistence: store,
                prescriptionEngine: PlanPrescriptionEngine(persistence: store),
                narrator: MorningBriefNarrator { _ in nil }
            ),
            missStore: BriefIntentMissStore(metadata: store.appMetadata),
            protectedData: protectedData,
            notificationPoster: notificationPoster,
            diagnosticsLog: DiagnosticsLog()
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

private final class RecordingBriefNotificationPoster: BriefNotificationPosting, @unchecked Sendable {
    private(set) var postedBrief: StoredDailyBrief?

    func postMorningBrief(_ brief: StoredDailyBrief) async -> Bool {
        postedBrief = brief
        return true
    }
}
