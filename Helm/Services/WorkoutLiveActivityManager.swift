@preconcurrency import ActivityKit
import Core
import Foundation

@MainActor
final class WorkoutLiveActivityManager {
    private var activityID: String?

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(session: WorkoutSessionDraft, currentExerciseName: String?) {
        guard isSupported else { return }
        end()

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
            content: .init(state: state, staleDate: nil),
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
        await activity.update(.init(state: state, staleDate: nil))
    }

    func end() {
        guard let activity = currentActivity() else {
            activityID = nil
            return
        }
        activityID = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func currentActivity() -> Activity<WorkoutActivityAttributes>? {
        guard let activityID else { return nil }
        return Activity<WorkoutActivityAttributes>.activities.first { $0.id == activityID }
    }
}
