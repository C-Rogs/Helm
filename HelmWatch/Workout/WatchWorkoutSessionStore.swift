import Core
import Foundation
import HealthKit
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
    /// True when Watch successfully started HealthKit mirroring to the phone.
    private(set) var isMirroringToCompanion = false

    private let manager: WatchWorkoutSessionManaging
    private let lifecycle = WatchWorkoutSessionLifecycleTracker()
    private let teardownTracker = LiveWorkoutBuilderTeardownTracker()
    private var elapsedTimer: Timer?
    /// Invoked on MainActor whenever live HR updates during an active/paused session.
    /// Skipped by callers when `isMirroringToCompanion` so phone uses HealthKit mirror path.
    var onLiveHeartRateBPM: ((Double) -> Void)?

    /// Full session setup synchronously: session + builder + data source + delegates +
    /// startActivity + beginCollection + mirroring. Called from `handle(_:)` before it returns.
    /// watchOS suspends cold-waked apps that don't reach a complete HKWorkoutSession
    /// before handle returns.
    func emergencyFullStart(configuration: HKWorkoutConfiguration, emergencySessionID: String) {
        guard phase == .idle || phase == .ended else { return }
        lastError = nil
        isMirroringToCompanion = false
        apply(.startRequested)
        sessionID = emergencySessionID
        lifecycle.begin(sessionID: emergencySessionID)
        manager.emergencyFullStart(configuration: configuration, sessionID: emergencySessionID)
        guard manager.hasActiveSession else {
            lastError = "Emergency session creation failed"
            lifecycle.end()
            sessionID = nil
            apply(.teardownFailed)
            return
        }
        isMirroringToCompanion = manager.isMirroringToCompanion
        startedAt = Date()
        apply(.sessionReady)
        startElapsedTimer()
    }

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
        isMirroringToCompanion = false
        apply(.startRequested)

        let id = UUID().uuidString
        sessionID = id
        lifecycle.begin(sessionID: id)

        do {
            try await manager.start(activity: selectedActivity, sessionID: id)
            isMirroringToCompanion = manager.isMirroringToCompanion
            startedAt = Date()
            apply(.sessionReady)
            startElapsedTimer()
        } catch {
            lastError = error.localizedDescription
            lifecycle.end()
            teardownTracker.end()
            sessionID = nil
            isMirroringToCompanion = false
            apply(.teardownFailed)
        }
    }

    /// Cold-wake / late adoption from phone: skip auth; align start with phone session when known.
    /// If emergencyFullStart already set up the session, just sync state without duplicating work.
    func startWorkout(fromPhoneConfiguration configuration: HKWorkoutConfiguration) async {
        guard phase == .idle || phase == .ended || phase == .active || phase == .paused else { return }
        lastError = nil
        isMirroringToCompanion = false

        // Emergency session already active -- just sync state and mirroring.
        if phase == .active || phase == .paused {
            let phoneStart = WatchCompanionBootstrap.coordinator.companionSessionStartedAt
            if let phoneStart {
                startedAt = phoneStart
            }
            isMirroringToCompanion = manager.isMirroringToCompanion
            startElapsedTimer()
            Task { await prepareHealthKit() }
            return
        }

        // Normal path: no emergency session, create from scratch.
        apply(.startRequested)

        let id = UUID().uuidString
        sessionID = id
        lifecycle.begin(sessionID: id)

        let phoneStart = WatchCompanionBootstrap.coordinator.companionSessionStartedAt
        do {
            try await manager.start(
                configuration: configuration,
                sessionID: id,
                activityStart: phoneStart
            )
            isMirroringToCompanion = manager.isMirroringToCompanion
            startedAt = phoneStart ?? Date()
            apply(.sessionReady)
            startElapsedTimer()
            // Warm auth/baselines in background for the next launch.
            Task { await prepareHealthKit() }
        } catch {
            lastError = error.localizedDescription
            lifecycle.end()
            teardownTracker.end()
            sessionID = nil
            isMirroringToCompanion = false
            apply(.teardownFailed)
            // Fall back: auth then normal start.
            await prepareHealthKit()
            await startWorkout()
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
            isMirroringToCompanion = false
            apply(.teardownSucceeded)
            sessionID = nil
            startedAt = nil
            elapsedSeconds = 0
        } catch {
            lastError = error.localizedDescription
            teardownTracker.end()
            lifecycle.end()
            sessionID = nil
            isMirroringToCompanion = false
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
            onLiveHeartRateBPM?(bpm)
        }
    }

    nonisolated func workoutSessionManagerDidLoseMirroring(_ manager: any WatchWorkoutSessionManaging) {
        Task { @MainActor in
            isMirroringToCompanion = false
            // Resume WCSession HR fallback with current reading if available.
            if let heartRateBPM {
                onLiveHeartRateBPM?(heartRateBPM)
            }
        }
    }
}
