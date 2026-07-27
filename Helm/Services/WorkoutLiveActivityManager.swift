@preconcurrency import ActivityKit
import Core
import Foundation

@MainActor
final class WorkoutLiveActivityManager {
    /// If the app stops updating (force quit, crash), the system can dismiss the Live Activity.
    static let staleInterval: TimeInterval = 5 * 60

    private var activityID: String?

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(session: WorkoutSessionDraft, currentExerciseName: String?) async {
        guard isSupported else { return }
        await endAll()

        let attributes = WorkoutActivityAttributes(
            sessionTitle: session.title ?? "Workout",
            startedAt: session.startedAt
        )
        let elapsed = Int(Date().timeIntervalSince(session.startedAt))
        let state = WorkoutActivityAttributes.ContentState(
            elapsedSeconds: max(elapsed, 0),
            currentExerciseName: currentExerciseName,
            restRemainingSeconds: nil
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
        restRemainingSeconds: Int?
    ) async {
        guard let activity = currentActivity() else { return }
        let elapsed = Int(Date().timeIntervalSince(session.startedAt))
        let state = WorkoutActivityAttributes.ContentState(
            elapsedSeconds: max(elapsed, 0),
            currentExerciseName: currentExerciseName,
            restRemainingSeconds: restRemainingSeconds
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

    private func staleDate(from now: Date = Date()) -> Date {
        now.addingTimeInterval(Self.staleInterval)
    }

    private func currentActivity() -> Activity<WorkoutActivityAttributes>? {
        guard let activityID else { return nil }
        return Activity<WorkoutActivityAttributes>.activities.first { $0.id == activityID }
    }
}
