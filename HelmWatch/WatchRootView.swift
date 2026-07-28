import Core
import SwiftUI

struct WatchRootView: View {
    @State private var coordinator = WatchSessionCoordinator(role: .watch)
    @State private var workoutStore = WatchWorkoutSessionStore()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            WatchWorkoutView(store: workoutStore, coordinator: coordinator)
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
        }
        .onChange(of: coordinator.workoutCompanionActive) { _, isActive in
            if isActive {
                guard workoutStore.phase == .idle || workoutStore.phase == .ended else { return }
                Task { await workoutStore.startWorkout() }
                return
            }
            guard workoutStore.phase == .active || workoutStore.phase == .paused else { return }
            Task { await workoutStore.endWorkout(discard: true) }
        }
        .onChange(of: workoutStore.heartRateBPM) { _, bpm in
            guard let bpm else { return }
            guard workoutStore.phase == .active || workoutStore.phase == .paused else { return }
            let day = HelmDay.day(for: .now, calendar: .current)
            coordinator.pushLiveHeartRate(Int(bpm.rounded()), helmDay: day)
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
