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

    init(
        persistence: PersistenceStore,
        workoutWriter: any WorkoutHealthKitWriting = WorkoutHealthKitWriter()
    ) {
        self.persistence = persistence
        self.workoutWriter = workoutWriter
    }

    func onSessionStarted(_ snapshot: ActiveSessionSnapshot) async {
        await notifications.requestPermissionIfNeeded()
        lifecycle.begin(sessionID: snapshot.session.id)
        liveActivity.start(
            session: snapshot.session,
            currentExerciseName: currentExerciseName(in: snapshot)
        )
    }

    func onSessionUpdated(_ snapshot: ActiveSessionSnapshot, restRemainingSeconds: Int?) async {
        await liveActivity.update(
            session: snapshot.session,
            currentExerciseName: currentExerciseName(in: snapshot),
            restRemainingSeconds: restRemainingSeconds
        )
    }

    func onEnterBackground(snapshot: ActiveSessionSnapshot, now: Date = Date()) async {
        guard let timer = snapshot.restTimer,
              timer.phase == .running,
              let endsAt = timer.endsAt else {
            return
        }
        await notifications.scheduleRestEndIfNeeded(
            sessionID: snapshot.session.id,
            endsAt: endsAt,
            now: now
        )
    }

    func onEnterForeground(sessionID: String) async {
        await notifications.cancelRestNotification(sessionID: sessionID)
    }

    func onSessionFinished(sessionID: String) async {
        await notifications.cancelRestNotification(sessionID: sessionID)
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
        guard let exercise = snapshot.session.exercises.last else { return nil }
        return (try? persistence.exercises.fetchSummary(id: exercise.exerciseID))?.displayName
    }
}
