import SwiftUI

struct WatchSyncStatusView: View {
    private var coordinator: WatchSessionCoordinator { WatchReadinessBootstrap.coordinator }

    var body: some View {
        List {
            Section("Session") {
                LabeledContent("Activation", value: activationLabel)
                LabeledContent("Paired", value: coordinator.isPaired ? "Yes" : "No")
                LabeledContent("Watch app installed", value: coordinator.isWatchAppInstalled ? "Yes" : "No")
                LabeledContent("Reachable", value: coordinator.isReachable ? "Yes" : "No")
                LabeledContent("Link", value: linkLabel)
            }

            Section("Companion") {
                LabeledContent("Active", value: coordinator.workoutCompanionActive ? "Yes" : "No")
                if let bpm = coordinator.latestLiveHeartRateBPM {
                    LabeledContent("Live HR", value: "\(bpm)")
                }
                if let name = coordinator.companionExerciseName {
                    LabeledContent("Exercise", value: name)
                }
            }

            Section("Round-trip") {
                LabeledContent("Status", value: coordinator.roundTripComplete ? "Complete" : "Pending")
                if let sent = coordinator.lastSent {
                    LabeledContent("Last sent", value: "#\(sent.sequence) (\(sent.helmDay))")
                }
                if let received = coordinator.lastReceived {
                    LabeledContent("Last received", value: "#\(received.sequence) from \(received.origin.rawValue)")
                }
                if let launchError = coordinator.lastLaunchError {
                    Text("Launch: \(launchError)")
                        .foregroundStyle(.red)
                }
                if let error = coordinator.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
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
}
