import Core
import Foundation
import HealthKitIngest
import Persistence

@MainActor
final class WorkoutSessionSideEffects {
    let lifecycle = WorkoutSessionLifecycleTracker()
    let notifications = RestTimerNotificationScheduler()
    let liveActivity = WorkoutLiveActivityManager()

    private let persistence: PersistenceStore
    private let workoutWriter: any WorkoutHealthKitWriting
    private let musicCapture: WorkoutMusicCaptureService

    init(
        persistence: PersistenceStore,
        workoutWriter: any WorkoutHealthKitWriting = WorkoutHealthKitWriter(),
        musicCapture: WorkoutMusicCaptureService? = nil
    ) {
        self.persistence = persistence
        self.workoutWriter = workoutWriter
        self.musicCapture = musicCapture ?? WorkoutMusicCaptureService(persistence: persistence)
    }

    func onSessionStarted(
        _ snapshot: ActiveSessionSnapshot,
        targetSummary: String? = nil,
        heartRateBPM: Int? = nil
    ) async {
        await notifications.requestPermissionIfNeeded()
        lifecycle.begin(sessionID: snapshot.session.id)
        musicCapture.reset()
        musicCapture.sampleIfChanged(sessionID: snapshot.session.id)
        await liveActivity.start(
            session: snapshot.session,
            currentExerciseName: currentExerciseName(in: snapshot),
            targetSummary: targetSummary,
            heartRateBPM: heartRateBPM
        )
    }

    func reconcileLiveActivitiesOnLaunch(hasActiveSession: Bool) async {
        await liveActivity.reconcileOrphanedActivities(hasActiveSession: hasActiveSession)
    }

    func endLiveActivitiesForTermination() {
        liveActivity.endAllForTermination()
    }

    func onSessionUpdated(
        _ snapshot: ActiveSessionSnapshot,
        restRemainingSeconds: Int?,
        targetSummary: String? = nil,
        heartRateBPM: Int? = nil
    ) async {
        musicCapture.sampleIfChanged(sessionID: snapshot.session.id)
        await liveActivity.update(
            session: snapshot.session,
            currentExerciseName: currentExerciseName(in: snapshot),
            targetSummary: targetSummary,
            restRemainingSeconds: restRemainingSeconds,
            heartRateBPM: heartRateBPM
        )
    }

    func onEnterBackground(snapshot: ActiveSessionSnapshot, restTimerSoundEnabled: Bool = true, now: Date = Date()) async {
        guard let timer = snapshot.restTimer,
              timer.phase == .running,
              let endsAt = timer.endsAt else {
            return
        }
        await notifications.scheduleRestEndIfNeeded(
            sessionID: snapshot.session.id,
            timerID: timer.id,
            endsAt: endsAt,
            soundEnabled: restTimerSoundEnabled,
            now: now
        )
    }

    func onEnterForeground(sessionID: String) async {
        await notifications.cancelRestNotification(sessionID: sessionID)
    }

    func resumeFromRestNotification(
        _ snapshot: ActiveSessionSnapshot,
        restRemainingSeconds: Int?
    ) async {
        await notifications.cancelRestNotification(sessionID: snapshot.session.id)
        let exerciseName = currentExerciseName(in: snapshot)
        await liveActivity.start(
            session: snapshot.session,
            currentExerciseName: exerciseName,
            targetSummary: nil,
            heartRateBPM: nil
        )
        await liveActivity.update(
            session: snapshot.session,
            currentExerciseName: exerciseName,
            targetSummary: nil,
            restRemainingSeconds: restRemainingSeconds,
            heartRateBPM: nil
        )
    }

    func onSessionFinished(sessionID: String) async {
        await notifications.cancelRestNotification(sessionID: sessionID)
        musicCapture.sampleIfChanged(sessionID: sessionID)
        musicCapture.reset()
        liveActivity.end()
        lifecycle.end()

        guard let session = try? persistence.workoutSessions.fetch(id: sessionID),
              let endedAt = session.endedAt else {
            return
        }

        _ = try? await workoutWriter.saveWorkout(
            WorkoutWriteRequest(
                sessionID: sessionID,
                startedAt: session.startedAt,
                endedAt: endedAt,
                title: session.title
            )
        )
    }

    func onSessionDiscarded(sessionID: String) async {
        await notifications.cancelRestNotification(sessionID: sessionID)
        liveActivity.end()
        lifecycle.end()
    }

    private func currentExerciseName(in snapshot: ActiveSessionSnapshot) -> String? {
        let exercise = snapshot.session.exercises.first { exercise in
            exercise.sets.contains { $0.status != .completed }
        } ?? snapshot.session.exercises.last
        guard let exercise else { return nil }
        return (try? persistence.exercises.fetchSummary(id: exercise.exerciseID))?.displayName
    }
}
