import Core
import SwiftUI

struct WatchRootView: View {
    private var coordinator: WatchSessionCoordinator { WatchCompanionBootstrap.coordinator }
    private var workoutStore: WatchWorkoutSessionStore { WatchCompanionBootstrap.workoutStore }
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            WatchWorkoutView(store: workoutStore, coordinator: coordinator) {
                Task { await WatchCompanionBootstrap.startCompanionWorkoutIfNeeded(playHaptic: true) }
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
            if coordinator.workoutCompanionActive {
                selectedTab = 0
            }
        }
        .onChange(of: coordinator.workoutCompanionActive) { _, isActive in
            if isActive {
                selectedTab = 0
            }
        }
        .onChange(of: coordinator.activationState) { _, state in
            guard state == .activated else { return }
            WatchCompanionBootstrap.flushLiveHeartRateIfNeeded()
        }
        .onChange(of: coordinator.isReachable) { _, reachable in
            guard reachable else { return }
            WatchCompanionBootstrap.flushLiveHeartRateIfNeeded()
        }
    }

    private var syncStatusTab: some View {
        List {
            Section("Signal") {
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
}

#Preview {
    WatchRootView()
}
