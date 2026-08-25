import Core
import SwiftUI

struct WatchRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                Task { await WatchCompanionBootstrap.syncCompanionWorkoutWithPhoneState() }
            }
        }
        .onChange(of: coordinator.workoutCompanionActive) { _, isActive in
            if isActive {
                selectedTab = 0
                Task { await WatchCompanionBootstrap.syncCompanionWorkoutWithPhoneState() }
            }
        }
        .onChange(of: coordinator.activationState) { _, state in
            guard state == .activated else { return }
            Task {
                await WatchCompanionBootstrap.syncCompanionWorkoutWithPhoneState()
                WatchCompanionBootstrap.flushLiveHeartRateIfNeeded()
            }
        }
        .onChange(of: coordinator.isReachable) { _, reachable in
            guard reachable else { return }
            Task {
                await WatchCompanionBootstrap.syncCompanionWorkoutWithPhoneState()
                WatchCompanionBootstrap.flushLiveHeartRateIfNeeded()
            }
        }
        .opacity(scenePhase == .active ? 1 : 0.4)
        .animation(
            WatchMotion.animation(WatchMotion.standardAnimation, reduceMotion: reduceMotion),
            value: scenePhase
        )
    }

    private var syncStatusTab: some View {
        List {
            Section {
                helmContextRows
            } header: {
                Text("Helm")
                    .watchType(.monoTag, color: WatchPalette.fgMuted)
            }
            .listRowBackground(WatchPalette.surface)

            Section {
                syncRows
            } header: {
                Text("Sync")
                    .watchType(.monoTag, color: WatchPalette.fgMuted)
            }
            .listRowBackground(WatchPalette.surface)
        }
        .helmWatchScreenBackground()
    }

    @ViewBuilder
    private var helmContextRows: some View {
        Text("Watch companion")
            .watchType(.title)

        if let received = coordinator.lastReceived {
            syncReadout("Phone day", value: received.helmDay, numeric: false)
            if let score = received.readinessScore {
                syncReadout(
                    "ARC",
                    value: "\(score)",
                    numeric: true,
                    color: WatchState.readiness(score: score).color
                )
            }
            syncReadout("Sequence", value: "#\(received.sequence)", numeric: true)
        } else if let error = coordinator.lastError {
            WatchErrorState(title: "No phone context", message: error, retryTitle: nil)
        } else if coordinator.activationState != .activated {
            WatchLoadingState(message: "Connecting")
        } else {
            WatchEmptyState(
                title: "Waiting for phone",
                message: "Open Helm on iPhone to sync today's ARC."
            )
        }
    }

    @ViewBuilder
    private var syncRows: some View {
        syncReadout("Activation", value: activationLabel, numeric: false)
        syncReadout("Reachable", value: coordinator.isReachable ? "Yes" : "No", numeric: false)
        syncReadout(
            "Link",
            value: coordinator.isReachable ? "Live" : "Reconnect",
            numeric: false,
            color: coordinator.isReachable ? WatchPalette.accent : WatchPalette.compromised
        )
        if let bpm = coordinator.latestLiveHeartRateBPM {
            syncReadout("Last HR sent", value: "\(bpm)", numeric: true)
        }
        syncReadout(
            "Round-trip",
            value: coordinator.roundTripComplete ? "Complete" : "Pending",
            numeric: false
        )
        if let sent = coordinator.lastSent {
            syncReadout("Last reply", value: "#\(sent.sequence)", numeric: true)
        }
        if let error = coordinator.lastError, coordinator.lastReceived != nil {
            WatchErrorState(title: "Sync error", message: error, retryTitle: nil)
        }
    }

    private func syncReadout(
        _ label: String,
        value: String,
        numeric: Bool,
        color: Color = WatchPalette.fg
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .watchType(.body, color: WatchPalette.fgSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(numeric ? WatchType.number.font : WatchType.body.font)
                .foregroundStyle(color)
                .multilineTextAlignment(.trailing)
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
        .helmWatchTheme()
}
