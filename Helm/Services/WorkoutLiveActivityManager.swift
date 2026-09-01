@preconcurrency import ActivityKit
import Core
import Foundation

@MainActor
final class WorkoutLiveActivityManager {
    /// Advance staleDate on updates so locked workouts do not go stale mid-session.
    static let staleInterval: TimeInterval = 20 * 60
    static let baselineRelevance: Double = 75
    static let elevatedRelevance: Double = 100
    static let heartbeatInterval: TimeInterval = 90

    private var activityID: String?
    private var lastScheduledUpdateAt: Date?
    private var lastPushedFingerprint: String?
    private var lastStaleRefreshAt: Date?
    private var isUpdateInFlight = false
    private var pendingUpdate: (id: String, content: ActivityContent<WorkoutActivityAttributes.ContentState>)?
    private var activityStateTask: Task<Void, Never>?
    private let minUpdateInterval: TimeInterval = 0.5

    /// Fired on main actor when the tracked activity ends or is dismissed while a session may still be active.
    var onActivityLost: (() -> Void)?

    var hasTrackedActivity: Bool {
        guard let activityID else { return false }
        return Activity<WorkoutActivityAttributes>.activities.contains { $0.id == activityID }
    }

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    static func relevanceScore(elevated: Bool) -> Double {
        elevated ? elevatedRelevance : baselineRelevance
    }

    func start(
        session: WorkoutSessionDraft,
        currentExerciseName: String?,
        targetSummary: String? = nil,
        heartRateBPM: Int? = nil,
        restRemainingSeconds: Int? = nil,
        restEndsAt: Date? = nil,
        elevatedRelevance: Bool = false
    ) async {
        await Self.reclaimMainThread()
        guard isSupported else { return }

        let state = makeContentState(
            session: session,
            currentExerciseName: currentExerciseName,
            targetSummary: targetSummary,
            restRemainingSeconds: restRemainingSeconds,
            restEndsAt: restEndsAt,
            heartRateBPM: heartRateBPM
        )

        if let activity = currentActivity() {
            scheduleUpdate(
                activityID: activity.id,
                state: state,
                elevatedRelevance: elevatedRelevance,
                forceStaleRefresh: false
            )
            return
        }

        if adoptSingleExistingActivity(matchingStartedAt: session.startedAt) {
            await update(
                session: session,
                currentExerciseName: currentExerciseName,
                targetSummary: targetSummary,
                restRemainingSeconds: restRemainingSeconds,
                restEndsAt: restEndsAt,
                heartRateBPM: heartRateBPM,
                elevatedRelevance: elevatedRelevance
            )
            return
        }

        if !Activity<WorkoutActivityAttributes>.activities.isEmpty {
            await endAll()
            await Self.reclaimMainThread()
        }

        let attributes = WorkoutActivityAttributes(
            sessionTitle: session.title ?? "Workout",
            startedAt: session.startedAt
        )
        let content = ActivityContent(
            state: state,
            staleDate: staleDate(),
            relevanceScore: Self.relevanceScore(elevated: elevatedRelevance)
        )
        let newID = await Self.requestActivity(attributes: attributes, content: content)
        await Self.reclaimMainThread()
        activityID = newID
        lastPushedFingerprint = Self.fingerprint(state)
        lastStaleRefreshAt = Date()
        if let newID {
            observeActivityState(activityID: newID)
        }
    }

    func update(
        session: WorkoutSessionDraft,
        currentExerciseName: String?,
        targetSummary: String? = nil,
        restRemainingSeconds: Int?,
        restEndsAt: Date? = nil,
        heartRateBPM: Int? = nil,
        elevatedRelevance: Bool = false,
        forceStaleRefresh: Bool = false
    ) async {
        guard isSupported else { return }
        if currentActivity() == nil {
            _ = adoptSingleExistingActivity(matchingStartedAt: session.startedAt)
        }
        guard let activity = currentActivity() else {
            await start(
                session: session,
                currentExerciseName: currentExerciseName,
                targetSummary: targetSummary,
                heartRateBPM: heartRateBPM,
                restRemainingSeconds: restRemainingSeconds,
                restEndsAt: restEndsAt,
                elevatedRelevance: elevatedRelevance
            )
            return
        }
        let state = makeContentState(
            session: session,
            currentExerciseName: currentExerciseName,
            targetSummary: targetSummary,
            restRemainingSeconds: restRemainingSeconds,
            restEndsAt: restEndsAt,
            heartRateBPM: heartRateBPM
        )
        scheduleUpdate(
            activityID: activity.id,
            state: state,
            elevatedRelevance: elevatedRelevance,
            forceStaleRefresh: forceStaleRefresh
        )
    }

    /// Foreground reclaim: re-request if lost, else bump relevance / staleDate.
    func reconcile(
        session: WorkoutSessionDraft,
        currentExerciseName: String?,
        targetSummary: String? = nil,
        heartRateBPM: Int? = nil,
        restRemainingSeconds: Int? = nil,
        restEndsAt: Date? = nil
    ) async {
        if hasTrackedActivity {
            await update(
                session: session,
                currentExerciseName: currentExerciseName,
                targetSummary: targetSummary,
                restRemainingSeconds: restRemainingSeconds,
                restEndsAt: restEndsAt,
                heartRateBPM: heartRateBPM,
                elevatedRelevance: true,
                forceStaleRefresh: true
            )
        } else {
            await start(
                session: session,
                currentExerciseName: currentExerciseName,
                targetSummary: targetSummary,
                heartRateBPM: heartRateBPM,
                restRemainingSeconds: restRemainingSeconds,
                restEndsAt: restEndsAt,
                elevatedRelevance: true
            )
        }
    }

    func end() {
        DispatchQueue.main.async {
            Task { @MainActor in await self.endAll() }
        }
    }

    func endAll() async {
        await Self.reclaimMainThread()
        activityStateTask?.cancel()
        activityStateTask = nil
        activityID = nil
        lastPushedFingerprint = nil
        lastStaleRefreshAt = nil
        let ids = Activity<WorkoutActivityAttributes>.activities.map(\.id)
        for id in ids {
            await Self.endActivity(id: id)
            await Self.reclaimMainThread()
        }
    }

    func reconcileOrphanedActivities(hasActiveSession: Bool) async {
        guard !hasActiveSession else { return }
        await endAll()
    }

    private func scheduleUpdate(
        activityID: String,
        state: WorkoutActivityAttributes.ContentState,
        elevatedRelevance: Bool,
        forceStaleRefresh: Bool
    ) {
        let fingerprint = Self.fingerprint(state)
        if !forceStaleRefresh, fingerprint == lastPushedFingerprint {
            return
        }

        let now = Date()
        if !forceStaleRefresh,
           let last = lastScheduledUpdateAt,
           now.timeIntervalSince(last) < minUpdateInterval,
           state.restRemainingSeconds != 0 {
            return
        }
        lastScheduledUpdateAt = now

        let content = ActivityContent(
            state: state,
            staleDate: staleDate(from: now),
            relevanceScore: Self.relevanceScore(elevated: elevatedRelevance)
        )
        pendingUpdate = (activityID, content)
        guard !isUpdateInFlight else { return }
        isUpdateInFlight = true
        drainPendingUpdates()
    }

    private func drainPendingUpdates() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                while let pending = self.pendingUpdate {
                    self.pendingUpdate = nil
                    let id = pending.id
                    let content = pending.content
                    guard let activity = Activity<WorkoutActivityAttributes>.activities.first(where: { $0.id == id }) else {
                        if self.activityID == id {
                            self.activityID = nil
                            self.lastPushedFingerprint = nil
                            self.onActivityLost?()
                        }
                        continue
                    }
                    await activity.update(content)
                    self.lastPushedFingerprint = Self.fingerprint(content.state)
                    self.lastStaleRefreshAt = Date()
                }
                self.isUpdateInFlight = false
                if self.pendingUpdate != nil {
                    self.isUpdateInFlight = true
                    self.drainPendingUpdates()
                }
            }
        }
    }

    private func observeActivityState(activityID: String) {
        activityStateTask?.cancel()
        activityStateTask = Task { @MainActor [weak self] in
            guard let activity = Activity<WorkoutActivityAttributes>.activities.first(where: { $0.id == activityID }) else {
                return
            }
            for await state in activity.activityStateUpdates {
                guard let self else { return }
                switch state {
                case .ended, .dismissed:
                    if self.activityID == activityID {
                        self.activityID = nil
                        self.lastPushedFingerprint = nil
                        self.onActivityLost?()
                    }
                    return
                case .active, .stale:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    private static func fingerprint(_ state: WorkoutActivityAttributes.ContentState) -> String {
        let exercise = state.currentExerciseName ?? ""
        let setNumber = state.currentSetNumber.map(String.init) ?? ""
        let setCount = state.currentSetCount.map(String.init) ?? ""
        let target = state.targetSummary ?? ""
        let endsAt = state.restEndsAt.map { String($0.timeIntervalSince1970) } ?? ""
        let rest = state.restRemainingSeconds.map(String.init) ?? ""
        let bpm = state.heartRateBPM.map(String.init) ?? ""
        let exerciseID = state.sessionExerciseID ?? ""
        let setID = state.currentSetID ?? ""
        return "\(exercise)|\(setNumber)|\(setCount)|\(target)|\(endsAt)|\(rest)|\(bpm)|\(exerciseID)|\(setID)"
    }

    nonisolated private static func requestActivity(
        attributes: WorkoutActivityAttributes,
        content: ActivityContent<WorkoutActivityAttributes.ContentState>
    ) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            DispatchQueue.main.async {
                Task { @MainActor in
                    let id = try? Activity.request(
                        attributes: attributes,
                        content: content,
                        pushType: nil
                    ).id
                    DispatchQueue.main.async {
                        continuation.resume(returning: id)
                    }
                }
            }
        }
    }

    nonisolated private static func endActivity(id: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                Task { @MainActor in
                    if let activity = Activity<WorkoutActivityAttributes>.activities.first(where: { $0.id == id }) {
                        await activity.end(nil, dismissalPolicy: .immediate)
                    }
                    DispatchQueue.main.async {
                        continuation.resume()
                    }
                }
            }
        }
    }

    nonisolated private static func reclaimMainThread() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
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
        let setCount = current?.sets.count
        return WorkoutActivityAttributes.ContentState(
            elapsedSeconds: elapsed,
            currentExerciseName: currentExerciseName,
            currentSetNumber: setNumber,
            currentSetCount: setCount,
            targetSummary: WatchCompanionSetLine.make(
                setNumber: setNumber,
                setCount: setCount,
                targetSummary: targetSummary
            ),
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

    @discardableResult
    private func adoptSingleExistingActivity(matchingStartedAt: Date) -> Bool {
        let activities = Activity<WorkoutActivityAttributes>.activities.filter {
            $0.attributes.startedAt == matchingStartedAt
        }
        guard activities.count == 1, let activity = activities.first else {
            return false
        }
        activityID = activity.id
        observeActivityState(activityID: activity.id)
        return true
    }
}
