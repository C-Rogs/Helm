import Core
import Foundation
import Observation

@MainActor
@Observable
public final class ActiveSessionStore {
    public private(set) var snapshot: ActiveSessionSnapshot?

    private let engine: ActiveSessionEngine

    public init(engine: ActiveSessionEngine) {
        self.engine = engine
    }

    public var hasActiveSession: Bool {
        snapshot != nil
    }

    public func recover() async {
        snapshot = try? await engine.recover()
    }

    public func start(title: String? = nil) async throws {
        snapshot = try await engine.start(title: title)
    }

    public func startFromTemplate(_ template: WorkoutTemplateDraft) async throws {
        snapshot = try await engine.startFromTemplate(template)
    }

    public func startFromPrescription(_ prescription: SessionPrescription) async throws {
        snapshot = try await engine.startFromPrescription(prescription)
    }

    public func startFromImport(_ plan: ImportedWorkoutPlan) async throws {
        snapshot = try await engine.startFromImport(plan)
    }

    public func logSet(setID: String, update: SetLogUpdate) async throws {
        snapshot = try await engine.logSet(setID: setID, update: update)
    }

    public func updateSetType(setID: String, setType: SetType) async throws {
        snapshot = try await engine.updateSetType(setID: setID, setType: setType)
    }

    public func completeSet(sessionExerciseID: String, setID: String) async throws {
        snapshot = try await engine.completeSet(sessionExerciseID: sessionExerciseID, setID: setID)
    }

    public func uncompleteSet(sessionExerciseID: String, setID: String) async throws {
        snapshot = try await engine.uncompleteSet(sessionExerciseID: sessionExerciseID, setID: setID)
    }

    public func addExercise(exerciseID: String, defaultSetCount: Int = 3, defaultRestSeconds: Int = 90) async throws {
        snapshot = try await engine.addExercise(
            exerciseID: exerciseID,
            defaultSetCount: defaultSetCount,
            defaultRestSeconds: defaultRestSeconds
        )
    }

    public func removeExercise(sessionExerciseID: String) async throws {
        snapshot = try await engine.removeExercise(sessionExerciseID: sessionExerciseID)
    }

    public func skipRest() async throws {
        snapshot = try await engine.skipRest()
    }

    public func finish() async throws -> String? {
        let sessionID = try await engine.finish()
        snapshot = nil
        return sessionID
    }

    public func discard() async throws {
        try await engine.discard()
        snapshot = nil
    }

    public func restTimer(at instant: Date? = nil) async throws -> RestTimer? {
        try await engine.restTimerProjection(at: instant)
    }

    public func remainingRestSeconds(at instant: Date? = nil) async throws -> Int? {
        guard let timer = try await restTimer(at: instant) else { return nil }
        let now = instant ?? Date()
        return timer.remainingSeconds(at: now)
    }

    public func syncFromPrescription(_ prescription: SessionPrescription) async throws {
        snapshot = try await engine.syncFromPrescription(prescription)
    }

    public func adjustExerciseSetCount(sessionExerciseID: String, targetSetCount: Int) async throws {
        snapshot = try await engine.adjustExerciseSetCount(
            sessionExerciseID: sessionExerciseID,
            targetSetCount: targetSetCount
        )
    }

    public func restoreExerciseLayout(_ exercises: [WorkoutSessionExerciseDraft]) async throws {
        snapshot = try await engine.restoreExerciseLayout(exercises)
    }

    public func updateSessionNotes(_ notes: String?) async throws {
        snapshot = try await engine.updateSessionNotes(notes)
    }

    public func reorderExercises(orderedSessionExerciseIDs: [String]) async throws {
        snapshot = try await engine.reorderExercises(orderedSessionExerciseIDs: orderedSessionExerciseIDs)
    }

    public func adjustRestTimer(deltaSeconds: Int) async throws {
        snapshot = try await engine.adjustRestTimer(deltaSeconds: deltaSeconds)
    }

    public func updateExerciseRest(sessionExerciseID: String, seconds: Int) async throws {
        snapshot = try await engine.updateExerciseRest(sessionExerciseID: sessionExerciseID, seconds: seconds)
    }
}
