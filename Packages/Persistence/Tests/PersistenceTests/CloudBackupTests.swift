import CoachLLM
import Core
import Foundation
import Testing
@testable import Persistence

@Suite("Cloud backup")
struct CloudBackupTests {
    private let benchPressID = "ex-bench"

    @Test("encodes and decodes profile backup")
    func profileRoundTrip() throws {
        let store = try PersistenceStore.inMemory()
        try seedExercise(in: store)
        try store.memoryProfile.save(
            MemoryProfile(
                baselinesSummary: "HRV baseline 60",
                preferences: "no machines"
            )
        )
        try store.trainingPlan.save(
            StoredTrainingPlanSettings(
                experienceRaw: "advanced",
                programTemplateRaw: "upper_lower",
                sessionDurationMinutes: 75
            )
        )
        try store.plan.saveMesocycleStateJSON(#"{"muscles":{},"pendingReactiveDeload":false,"consecutiveDepletedDays":0}"#)
        let bodyData = try JSONEncoder().encode(
            BodyProfile(
                bodyMassKg: 82.5,
                heightCm: 180,
                biologicalSex: .male,
                dateOfBirth: Date(timeIntervalSince1970: 632_448_000)
            )
        )
        guard let bodyJSON = String(data: bodyData, encoding: .utf8) else {
            Issue.record("body profile JSON encoding failed")
            return
        }
        try store.appMetadata.setValue(bodyJSON, forKey: CloudBackupService.bodyProfileMetadataKey)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("helm-cloud-backup-\(UUID().uuidString)", isDirectory: true)
        let fileStore = LocalDirectoryCloudBackupFileStore(rootURL: root)
        let service = CloudBackupService(store: store, fileStore: fileStore)

        let backup = try service.buildProfileBackup(onboardingCompleted: true)
        #expect(backup.memoryProfile.baselinesSummary == "HRV baseline 60")
        #expect(backup.trainingPlanSettings.experienceRaw == "advanced")
        #expect(backup.bodyProfile?.bodyMassKg == 82.5)
        #expect(backup.onboardingCompleted)

        let data = try service.encodeProfile(backup)
        #expect(data.count > 50)
        let decoded = try service.decodeProfile(data)
        #expect(decoded.memoryProfile.preferences == "no machines")
        #expect(decoded.mesocycleStateJSON != nil)
    }

    @Test("size estimate includes profile and history")
    func sizeEstimate() throws {
        let store = try PersistenceStore.inMemory()
        try seedExercise(in: store)
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        try store.workoutSessions.insert(sampleSession(startedAt: started))

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("helm-cloud-size-\(UUID().uuidString)", isDirectory: true)
        let service = CloudBackupService(
            store: store,
            fileStore: LocalDirectoryCloudBackupFileStore(rootURL: root)
        )
        let estimate = try service.estimateSizes(
            onboardingCompleted: false,
            now: started.addingTimeInterval(86_400)
        )
        #expect(estimate.profileByteCount > 20)
        #expect(estimate.historyByteCount > 50)
        #expect(estimate.historySessionCount == 1)
    }

    @Test("push and pull restores profile last-write-wins")
    func pushPullLWW() throws {
        let source = try PersistenceStore.inMemory()
        try seedExercise(in: source)
        try source.memoryProfile.save(MemoryProfile(whatHasWorked: "heavy singles"))
        try source.trainingPlan.save(
            StoredTrainingPlanSettings(programTemplateRaw: "full_body")
        )

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("helm-cloud-lww-\(UUID().uuidString)", isDirectory: true)
        let fileStore = LocalDirectoryCloudBackupFileStore(rootURL: root)
        let sourceService = CloudBackupService(store: source, fileStore: fileStore)
        let pushTime = Date(timeIntervalSince1970: 1_800_100_000)
        let push = try sourceService.push(
            includeHistory: false,
            onboardingCompleted: true,
            now: pushTime
        )
        #expect(push.profileUpdatedAt == pushTime)

        let destination = try PersistenceStore.inMemory()
        var appliedOnboarding: Bool?
        let destService = CloudBackupService(store: destination, fileStore: fileStore)
        let result = try destService.pullIfNeeded(
            includeHistory: false,
            lastAppliedProfileUpdatedAt: nil,
            forceIfFreshInstall: true,
            applyOnboardingCompleted: { appliedOnboarding = $0 }
        )
        #expect(result.didRestoreProfile)
        #expect(appliedOnboarding == true)
        #expect(try destination.memoryProfile.load().whatHasWorked == "heavy singles")
        #expect(try destination.trainingPlan.load().programTemplateRaw == "full_body")

        let skipped = try destService.pullIfNeeded(
            includeHistory: false,
            lastAppliedProfileUpdatedAt: pushTime,
            forceIfFreshInstall: false,
            applyOnboardingCompleted: { _ in }
        )
        #expect(!skipped.didRestoreProfile)
    }

    @Test("push with history imports sessions idempotently")
    func historyImport() throws {
        let source = try PersistenceStore.inMemory()
        try seedExercise(in: source)
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        try source.workoutSessions.insert(sampleSession(startedAt: started))

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("helm-cloud-hist-\(UUID().uuidString)", isDirectory: true)
        let fileStore = LocalDirectoryCloudBackupFileStore(rootURL: root)
        let sourceService = CloudBackupService(store: source, fileStore: fileStore)
        _ = try sourceService.push(
            includeHistory: true,
            onboardingCompleted: false,
            now: started.addingTimeInterval(86_400)
        )

        let destination = try PersistenceStore.inMemory()
        try seedExercise(in: destination)
        let destService = CloudBackupService(store: destination, fileStore: fileStore)
        let first = try destService.pullForced(
            includeHistory: true,
            applyOnboardingCompleted: { _ in }
        )
        #expect(first.historyImport?.importedSessionCount == 1)

        let second = try destService.pullForced(
            includeHistory: true,
            applyOnboardingCompleted: { _ in }
        )
        #expect(second.historyImport?.importedSessionCount == 0)
        #expect(try destination.workoutSessions.fetch(id: "session-cloud-1") != nil)
    }

    private func seedExercise(in store: PersistenceStore) throws {
        try store.exercises.upsert(
            id: benchPressID,
            canonicalName: "bench press barbell",
            displayName: "Bench Press (Barbell)",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "chest"
        )
    }

    private func sampleSession(startedAt: Date) -> WorkoutSessionDraft {
        WorkoutSessionDraft(
            id: "session-cloud-1",
            title: "Push",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(3600),
            status: .completed,
            source: .manual,
            exercises: [
                WorkoutSessionExerciseDraft(
                    id: "wse-cloud-1",
                    exerciseID: benchPressID,
                    displayOrder: 0,
                    exerciseMode: .weightReps,
                    sets: [
                        SetEntryDraft(
                            id: "set-cloud-1",
                            setIndex: 1,
                            setType: .normal,
                            status: .completed,
                            mass: Mass(kilograms: 100),
                            reps: 5,
                            completedAt: startedAt
                        )
                    ]
                )
            ]
        )
    }
}
