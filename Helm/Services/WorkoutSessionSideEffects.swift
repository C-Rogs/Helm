import Core
import Foundation
import HealthKitIngest
import OSLog
import Persistence

@MainActor
final class WorkoutSessionSideEffects {
    private static let logger = Logger(subsystem: "com.cameronro.helm", category: "WorkoutSessionSideEffects")

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
        musicCapture.startPolling(sessionID: snapshot.session.id)
        await liveActivity.start(
            session: snapshot.session,
            currentExerciseName: currentExerciseName(in: snapshot),
            targetSummary: targetSummary,
            heartRateBPM: heartRateBPM
        )
    }

    /// Restores side effects after kill/background without tearing down an existing Live Activity.
    func resumePersistedSession(
        _ snapshot: ActiveSessionSnapshot,
        restRemainingSeconds: Int?,
        targetSummary: String? = nil,
        heartRateBPM: Int? = nil,
        restTimerSoundEnabled: Bool = true
    ) async {
        await notifications.requestPermissionIfNeeded()
        lifecycle.begin(sessionID: snapshot.session.id)
        musicCapture.sampleIfChanged(sessionID: snapshot.session.id)
        musicCapture.startPolling(sessionID: snapshot.session.id)
        let exerciseName = currentExerciseName(in: snapshot)
        let endsAt: Date? = {
            guard let remaining = restRemainingSeconds, remaining > 0 else { return nil }
            return snapshot.restTimer?.endsAt
        }()
        await liveActivity.start(
            session: snapshot.session,
            currentExerciseName: exerciseName,
            targetSummary: targetSummary,
            heartRateBPM: heartRateBPM,
            restRemainingSeconds: restRemainingSeconds,
            restEndsAt: endsAt
        )
        await syncRestEndNotification(
            snapshot: snapshot,
            restTimerSoundEnabled: restTimerSoundEnabled
        )
    }

    func reconcileLiveActivitiesOnLaunch(hasActiveSession: Bool) async {
        await liveActivity.reconcileOrphanedActivities(hasActiveSession: hasActiveSession)
    }

    func endLiveActivitiesForTermination() async {
        await liveActivity.endAll()
    }

    func onSessionUpdated(
        _ snapshot: ActiveSessionSnapshot,
        restRemainingSeconds: Int?,
        targetSummary: String? = nil,
        heartRateBPM: Int? = nil,
        restTimerSoundEnabled: Bool = true
    ) async {
        musicCapture.sampleIfChanged(sessionID: snapshot.session.id)
        let endsAt: Date? = {
            guard let remaining = restRemainingSeconds, remaining > 0 else { return nil }
            return snapshot.restTimer?.endsAt
        }()
        await liveActivity.update(
            session: snapshot.session,
            currentExerciseName: currentExerciseName(in: snapshot),
            targetSummary: targetSummary,
            restRemainingSeconds: restRemainingSeconds,
            restEndsAt: endsAt,
            heartRateBPM: heartRateBPM
        )
        await syncRestEndNotification(
            snapshot: snapshot,
            restTimerSoundEnabled: restTimerSoundEnabled
        )
    }

    func syncRestEndNotification(
        snapshot: ActiveSessionSnapshot,
        restTimerSoundEnabled: Bool = true,
        now: Date = Date()
    ) async {
        guard let timer = snapshot.restTimer,
              timer.phase == .running,
              let endsAt = timer.endsAt else {
            await notifications.cancelRestNotification(sessionID: snapshot.session.id)
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

    func onEnterBackground(snapshot: ActiveSessionSnapshot, restTimerSoundEnabled: Bool = true, now: Date = Date()) async {
        await syncRestEndNotification(
            snapshot: snapshot,
            restTimerSoundEnabled: restTimerSoundEnabled,
            now: now
        )
    }

    func onEnterForeground(sessionID: String) async {
        // Keep the rest-end notification armed while the timer is running.
        // Foreground delivery is suppressed in HelmNotificationDelegate; cancelling here
        // left users with no sound when the app was backgrounded again before rest ended.
    }

    func resumeFromRestNotification(
        _ snapshot: ActiveSessionSnapshot,
        restRemainingSeconds: Int?
    ) async {
        await notifications.cancelRestNotification(sessionID: snapshot.session.id)
        await resumePersistedSession(
            snapshot,
            restRemainingSeconds: restRemainingSeconds
        )
    }

    func onSessionFinished(sessionID: String, writePhoneEnergyEstimate: Bool = true) async {
        await notifications.cancelRestNotification(sessionID: sessionID)
        musicCapture.sampleIfChanged(sessionID: sessionID)
        musicCapture.reset()
        liveActivity.end()
        lifecycle.end()

        guard writePhoneEnergyEstimate else { return }

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
        musicCapture.reset()
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
