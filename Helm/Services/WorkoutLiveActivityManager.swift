@preconcurrency import ActivityKit
import Core
import Foundation

@MainActor
final class WorkoutLiveActivityManager {
    /// If the app stops updating (force quit, crash), the system can dismiss the Live Activity.
    static let staleInterval: TimeInterval = 5 * 60

    private var activityID: String?

    var hasTrackedActivity: Bool {
        guard let activityID else { return false }
        return Activity<WorkoutActivityAttributes>.activities.contains { $0.id == activityID }
    }

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(
        session: WorkoutSessionDraft,
        currentExerciseName: String?,
        targetSummary: String? = nil,
        heartRateBPM: Int? = nil
    ) async {
        guard isSupported else { return }
        await endAll()

        let attributes = WorkoutActivityAttributes(
            sessionTitle: session.title ?? "Workout",
            startedAt: session.startedAt
        )
        let state = makeContentState(
            session: session,
            currentExerciseName: currentExerciseName,
            targetSummary: targetSummary,
            restRemainingSeconds: nil,
            restEndsAt: nil,
            heartRateBPM: heartRateBPM
        )

        if let activity = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: staleDate()),
            pushType: nil
        ) {
            activityID = activity.id
        }
    }

    func update(
        session: WorkoutSessionDraft,
        currentExerciseName: String?,
        targetSummary: String? = nil,
        restRemainingSeconds: Int?,
        restEndsAt: Date? = nil,
        heartRateBPM: Int? = nil
    ) async {
        guard let activity = currentActivity() else { return }
        let state = makeContentState(
            session: session,
            currentExerciseName: currentExerciseName,
            targetSummary: targetSummary,
            restRemainingSeconds: restRemainingSeconds,
            restEndsAt: restEndsAt,
            heartRateBPM: heartRateBPM
        )
        await activity.update(.init(state: state, staleDate: staleDate()))
    }

    func end() {
        Task { await endAll() }
    }

    func endAll() async {
        activityID = nil
        for activity in Activity<WorkoutActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Best-effort teardown when iOS terminates the process (not guaranteed on force quit).
    func endAllForTermination() {
        let semaphore = DispatchSemaphore(value: 0)
        Task { @MainActor in
            await endAll()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)
    }

    /// Clears Live Activities left behind after force quit when no session is recoverable.
    func reconcileOrphanedActivities(hasActiveSession: Bool) async {
        guard !hasActiveSession else { return }
        await endAll()
    }

    private func makeContentState(
        session: WorkoutSessionDraft,
        currentExerciseName: String?,
        targetSummary: String?,
        restRemainingSeconds: Int?,
        restEndsAt: Date?,
        heartRateBPM: Int?,
        now: Date = Date()
    ) -> WorkoutActivityAttributes.ContentState {
        let elapsed = max(0, Int(now.timeIntervalSince(session.startedAt)))
        let current = session.exercises.first { exercise in
            exercise.sets.contains { $0.status != .completed }
        } ?? session.exercises.first
        let setNumber = current.flatMap { exercise in
            exercise.sets.firstIndex { $0.status != .completed }.map { $0 + 1 }
        }
        let setID = current.flatMap { exercise in
            exercise.sets.first { $0.status != .completed }?.id
        }
        return WorkoutActivityAttributes.ContentState(
            elapsedSeconds: elapsed,
            currentExerciseName: currentExerciseName,
            currentSetNumber: setNumber,
            currentSetCount: current?.sets.count,
            targetSummary: targetSummary,
            restRemainingSeconds: restRemainingSeconds,
            restEndsAt: restEndsAt,
            heartRateBPM: heartRateBPM,
            sessionExerciseID: current?.id,
            currentSetID: setID
        )
    }

    private func staleDate(from now: Date = Date()) -> Date {
        now.addingTimeInterval(Self.staleInterval)
    }

    private func currentActivity() -> Activity<WorkoutActivityAttributes>? {
        guard let activityID else { return nil }
        return Activity<WorkoutActivityAttributes>.activities.first { $0.id == activityID }
    }
}
