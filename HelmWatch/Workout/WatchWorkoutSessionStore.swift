import Core
import Foundation
import Observation

@MainActor
@Observable
final class WatchWorkoutSessionStore {
    private(set) var phase: WatchWorkoutSessionPhase = .idle
    private(set) var selectedActivity: WatchWorkoutActivityKind = .traditionalStrengthTraining
    private(set) var sessionID: String?
    private(set) var startedAt: Date?
    private(set) var elapsedSeconds: Int = 0
    private(set) var heartRateBPM: Double?
    private(set) var heartRateZone: HeartRateZone?
    private(set) var lastError: String?
    private(set) var isHealthKitAuthorized = false

    private let manager: WatchWorkoutSessionManaging
    private let lifecycle = WatchWorkoutSessionLifecycleTracker()
    private let teardownTracker = LiveWorkoutBuilderTeardownTracker()
    private var elapsedTimer: Timer?

    init(manager: WatchWorkoutSessionManaging = WatchWorkoutSessionManager()) {
        self.manager = manager
        self.manager.delegate = self
    }

    func prepareHealthKit() async {
        do {
            isHealthKitAuthorized = try await manager.requestAuthorization()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func selectActivity(_ activity: WatchWorkoutActivityKind) {
        guard phase == .idle || phase == .ended else { return }
        selectedActivity = activity
    }

    func startWorkout() async {
        guard phase == .idle || phase == .ended else { return }
        lastError = nil
        apply(.startRequested)

        let id = UUID().uuidString
        sessionID = id
        lifecycle.begin(sessionID: id)

        do {
            try await manager.start(activity: selectedActivity, sessionID: id)
            startedAt = Date()
            apply(.sessionReady)
            startElapsedTimer()
        } catch {
            lastError = error.localizedDescription
            lifecycle.end()
            teardownTracker.end()
            sessionID = nil
            apply(.teardownFailed)
        }
    }

    func togglePause() async {
        switch phase {
        case .active:
            manager.pause()
            apply(.pause)
            lifecycle.markPauseResume()
            stopElapsedTimer()
        case .paused:
            manager.resume()
            apply(.resume)
            lifecycle.markPauseResume()
            startElapsedTimer()
        default:
            break
        }
    }

    func endWorkout(discard: Bool) async {
        guard phase == .active || phase == .paused else { return }
        lastError = nil
        apply(.endRequested)
        stopElapsedTimer()

        if let sessionID {
            teardownTracker.begin(sessionID: sessionID)
        }

        do {
            try await manager.end(discard: discard)
            teardownTracker.end()
            lifecycle.end()
            heartRateBPM = nil
            heartRateZone = nil
            apply(.teardownSucceeded)
            sessionID = nil
            startedAt = nil
            elapsedSeconds = 0
        } catch {
            lastError = error.localizedDescription
            teardownTracker.end()
            lifecycle.end()
            sessionID = nil
            apply(.teardownFailed)
        }
    }

    private func apply(_ event: WatchWorkoutSessionEvent) {
        guard let next = WatchWorkoutSessionReducer.reduce(phase: phase, event: event) else { return }
        phase = next
    }

    private func startElapsedTimer() {
        stopElapsedTimer()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsedSeconds = max(0, Int(Date().timeIntervalSince(startedAt)))
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }
}

extension WatchWorkoutSessionStore: WatchWorkoutSessionManagerDelegate {
    nonisolated func workoutSessionManager(
        _ manager: any WatchWorkoutSessionManaging,
        didUpdateHeartRate bpm: Double,
        restingHR: Double,
        maxHR: Double
    ) {
        Task { @MainActor in
            guard phase == .active || phase == .paused else { return }
            heartRateBPM = bpm
            heartRateZone = HeartRateZone.zone(
                heartRateBPM: bpm,
                restingHR: restingHR,
                maxHR: maxHR
            )
        }
    }
}
