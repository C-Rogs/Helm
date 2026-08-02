import Core
import SwiftUI
import WatchKit

struct WatchRootView: View {
    @State private var coordinator = WatchSessionCoordinator(role: .watch)
    @State private var workoutStore = WatchWorkoutSessionStore()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            WatchWorkoutView(store: workoutStore, coordinator: coordinator) {
                Task { await startCompanionWorkoutIfNeeded(playHaptic: true) }
            }
                .tabItem {
                    Label("Workout", systemImage: "heart.fill")
                }
                .tag(0)

            NavigationStack {
                WatchBriefView(coordinator: coordinator)
            }
            .tabItem {
                Label("Brief", systemImage: "sun.max.fill")
            }
            .tag(1)

            syncStatusTab
                .tabItem {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .tag(2)
        }
        .onOpenURL { url in
            guard url.absoluteString == WatchSyncPayload.briefDeepLink else { return }
            selectedTab = 1
        }
        .onAppear {
            coordinator.hydrateFromReceivedApplicationContext()
            wireHeartRatePush()
            WatchWorkoutLaunchBridge.shared.onPendingLaunch = {
                selectedTab = 0
                Task { await consumePhoneLaunchIfNeeded() }
            }
            Task {
                await consumePhoneLaunchIfNeeded()
                // Hydrate may set companion active without an onChange edge; start HR then.
                guard coordinator.workoutCompanionActive else { return }
                selectedTab = 0
                await startCompanionWorkoutIfNeeded(playHaptic: true)
            }
        }
        .onChange(of: coordinator.workoutCompanionActive) { _, isActive in
            if isActive {
                selectedTab = 0
                Task { await startCompanionWorkoutIfNeeded(playHaptic: true) }
                return
            }
            guard workoutStore.phase == .active || workoutStore.phase == .paused else { return }
            let discard = !coordinator.companionSaveWatchWorkout
            Task { await workoutStore.endWorkout(discard: discard) }
        }
        .onChange(of: coordinator.activationState) { _, state in
            guard state == .activated else { return }
            flushLiveHeartRateIfNeeded()
        }
        .onChange(of: coordinator.isReachable) { _, reachable in
            guard reachable else { return }
            flushLiveHeartRateIfNeeded()
        }
    }

    private var syncStatusTab: some View {
        List {
            Section("Helm") {
                Text("Watch companion")
                    .font(.headline)
                if let received = coordinator.lastReceived {
                    LabeledContent("Phone day", value: received.helmDay)
                    if let score = received.readinessScore {
                        LabeledContent("ARC", value: "\(score)")
                    }
                    LabeledContent("Sequence", value: "#\(received.sequence)")
                } else {
                    Text("Waiting for phone context")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Sync") {
                LabeledContent("Activation", value: activationLabel)
                LabeledContent("Reachable", value: coordinator.isReachable ? "Yes" : "No")
                LabeledContent("Link", value: coordinator.isReachable ? "Live" : "Reconnect")
                if let bpm = coordinator.latestLiveHeartRateBPM {
                    LabeledContent("Last HR sent", value: "\(bpm)")
                }
                LabeledContent("Round-trip", value: coordinator.roundTripComplete ? "Complete" : "Pending")
                if let sent = coordinator.lastSent {
                    LabeledContent("Last reply", value: "#\(sent.sequence)")
                }
                if let error = coordinator.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var activationLabel: String {
        switch coordinator.activationState {
        case .notActivated: "Not activated"
        case .inactive: "Inactive"
        case .activated: "Activated"
        @unknown default: "Unknown"
        }
    }

    private func wireHeartRatePush() {
        workoutStore.onLiveHeartRateBPM = { [coordinator] bpm in
            guard workoutStore.phase == .active || workoutStore.phase == .paused else { return }
            let day = HelmDay.day(for: .now, calendar: .current)
            coordinator.pushLiveHeartRate(Int(bpm.rounded()), helmDay: day)
        }
    }

    private func flushLiveHeartRateIfNeeded() {
        guard let bpm = workoutStore.heartRateBPM else { return }
        guard workoutStore.phase == .active || workoutStore.phase == .paused else { return }
        let day = HelmDay.day(for: .now, calendar: .current)
        coordinator.pushLiveHeartRate(Int(bpm.rounded()), helmDay: day, force: true)
    }

    private func consumePhoneLaunchIfNeeded() async {
        guard let configuration = WatchWorkoutLaunchBridge.shared.consumePendingConfiguration() else {
            return
        }
        let kind = WatchWorkoutActivityKind.fromHealthKitActivityTypeRawValue(
            configuration.activityType.rawValue
        )
        workoutStore.selectActivity(kind)
        selectedTab = 0
        await startCompanionWorkoutIfNeeded(playHaptic: true)
    }

    private func startCompanionWorkoutIfNeeded(playHaptic: Bool) async {
        guard workoutStore.phase == .idle || workoutStore.phase == .ended else { return }
        if playHaptic {
            WKInterfaceDevice.current().play(.start)
        }
        await workoutStore.prepareHealthKit()
        await workoutStore.startWorkout()
        flushLiveHeartRateIfNeeded()
    }
}

#Preview {
    WatchRootView()
}
