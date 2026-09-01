import Core
import SwiftUI

struct WatchRootView: View {
    @AppStorage("helm.watch.showsSyncTab") private var showsSyncTab = false
    private var coordinator: WatchSessionCoordinator { WatchCompanionBootstrap.coordinator }
    private var workoutStore: WatchWorkoutSessionStore { WatchCompanionBootstrap.workoutStore }
    @State private var selectedTab = 0

    private var isSessionChrome: Bool {
        coordinator.workoutCompanionActive
            || workoutStore.phase == .preparing
            || workoutStore.phase == .active
            || workoutStore.phase == .paused
            || workoutStore.phase == .ending
    }

    var body: some View {
        Group {
            if isSessionChrome {
                workoutPane
            } else {
                tabShell
            }
        }
        .onOpenURL { url in
            guard url.absoluteString == WatchSyncPayload.briefDeepLink else { return }
            selectedTab = 1
        }
        .onAppear(perform: syncIfCompanionActive)
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
        .onChange(of: showsSyncTab) { _, visible in
            if !visible, selectedTab == 2 {
                selectedTab = 1
            }
        }
    }

    private var workoutPane: some View {
        WatchWorkoutView(store: workoutStore, coordinator: coordinator) {
            Task { await WatchCompanionBootstrap.startCompanionWorkoutIfNeeded(playHaptic: true) }
        }
    }

    private var tabShell: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                WatchWorkoutView(store: workoutStore, coordinator: coordinator) {
                    Task { await WatchCompanionBootstrap.startCompanionWorkoutIfNeeded(playHaptic: true) }
                }
            }
            .tabItem {
                Label("Workout", systemImage: "heart.fill")
            }
            .tag(0)

            NavigationStack {
                WatchBriefView(coordinator: coordinator, showsSyncTab: $showsSyncTab)
            }
            .tabItem {
                Label("Brief", systemImage: "sun.max.fill")
            }
            .tag(1)

            if showsSyncTab {
                syncStatusTab
                    .tabItem {
                        Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .tag(2)
            }
        }
    }

    private func syncIfCompanionActive() {
        if coordinator.workoutCompanionActive {
            selectedTab = 0
            Task { await WatchCompanionBootstrap.syncCompanionWorkoutWithPhoneState() }
        }
    }

    private var syncStatusTab: some View {
        List {
            Section {
                helmContextRows
            } header: {
                Text("Signal")
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
                message: "Open Signal on iPhone to sync today's ARC."
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
