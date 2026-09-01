import DesignSystem
import SwiftUI

struct WatchSyncStatusView: View {
    private var coordinator: WatchSessionCoordinator { WatchReadinessBootstrap.coordinator }
    @State private var showsAdvancedDetail = false

    var body: some View {
        List {
            Section {
                Text(
                    "Train always starts a phone workout session so HealthKit can pull heart rate from AirPods Pro or another paired sensor when available. If the Signal Watch app is installed, raising your wrist also joins the Watch companion for live HR and set controls. Wrist-down Watch will not run third-party workout code until you raise or open the app."
                )
                .helmType(.body, color: HelmColor.fgMuted)
                .helmListRowChrome()
            } header: {
                Text("How heart rate works")
            }

            Section("Session") {
                HelmStatusRow(label: "Activation", value: activationLabel)
                    .helmListRowChrome()
                HelmStatusRow(label: "Paired", value: coordinator.isPaired ? "Yes" : "No")
                    .helmListRowChrome()
                HelmStatusRow(label: "Watch app installed", value: coordinator.isWatchAppInstalled ? "Yes" : "No")
                    .helmListRowChrome()
                HelmStatusRow(label: "Reachable", value: coordinator.isReachable ? "Yes" : "No")
                    .helmListRowChrome()
                HelmStatusRow(
                    label: "Link",
                    value: linkLabel,
                    valueColor: coordinator.isCompanionLive ? HelmColor.ready : HelmColor.fgMuted
                )
                .helmListRowChrome()
            }

            Section("Companion") {
                HelmStatusRow(
                    label: "Train companion",
                    value: coordinator.workoutCompanionActive ? "Yes" : "No"
                )
                .helmListRowChrome()
                HelmStatusRow(
                    label: "Watch workout",
                    value: coordinator.watchWorkoutActive ? "Yes" : "No"
                )
                .helmListRowChrome()
                Text(
                    "Watch workout is the wrist HealthKit session. Train companion is only when you start on iPhone. Heart rate can show from a Watch-only session."
                )
                .helmType(.body, color: HelmColor.fgMuted)
                .helmListRowChrome()
                if let bpm = coordinator.latestLiveHeartRateBPM {
                    HelmStatusRow(label: "Live HR", value: "\(bpm)")
                        .helmListRowChrome()
                }
                if let name = coordinator.companionExerciseName {
                    HelmStatusRow(label: "Exercise", value: name)
                        .helmListRowChrome()
                }
            }

            Section {
                Toggle("Show advanced detail", isOn: $showsAdvancedDetail)
                    .helmListRowChrome()
            }

            if showsAdvancedDetail {
                Section("Round-trip") {
                    HelmStatusRow(
                        label: "Status",
                        value: coordinator.roundTripComplete ? "Complete" : "Pending"
                    )
                    .helmListRowChrome()
                    if let sent = coordinator.lastSent {
                        HelmStatusRow(label: "Last sent", value: "#\(sent.sequence) (\(sent.helmDay))")
                            .helmListRowChrome()
                    }
                    if let received = coordinator.lastReceived {
                        HelmStatusRow(
                            label: "Last received",
                            value: "#\(received.sequence) from \(received.origin.rawValue)"
                        )
                        .helmListRowChrome()
                    }
                    if let launchError = coordinator.lastLaunchError {
                        Label("Launch: \(launchError)", systemImage: "exclamationmark.triangle.fill")
                            .helmType(.body, color: HelmColor.depleted)
                            .helmListRowChrome()
                    }
                    if let error = coordinator.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .helmType(.body, color: HelmColor.depleted)
                            .helmListRowChrome()
                    }
                }
            }
        }
        .helmSettingsListChrome()
        .navigationTitle("Watch Sync")
        .onAppear {
            coordinator.refreshPairingFlags()
            coordinator.hydrateFromReceivedApplicationContext()
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

    private var linkLabel: String {
        if coordinator.isCompanionLive {
            return "Live"
        }
        if coordinator.isReachable {
            return "Reachable"
        }
        return "Reconnect"
    }
}

#Preview {
    NavigationStack {
        WatchSyncStatusView()
    }
    .helmTheme()
}
