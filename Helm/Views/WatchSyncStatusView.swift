import SwiftUI

struct WatchSyncStatusView: View {
    @State private var coordinator = WatchSessionCoordinator(role: .phone)

    var body: some View {
        List {
            Section("Session") {
                LabeledContent("Activation", value: activationLabel)
                LabeledContent("Paired", value: coordinator.isPaired ? "Yes" : "No")
                LabeledContent("Watch app installed", value: coordinator.isWatchAppInstalled ? "Yes" : "No")
                LabeledContent("Reachable", value: coordinator.isReachable ? "Yes" : "No")
            }

            Section("Round-trip") {
                LabeledContent("Status", value: coordinator.roundTripComplete ? "Complete" : "Pending")
                if let sent = coordinator.lastSent {
                    LabeledContent("Last sent", value: "#\(sent.sequence) (\(sent.helmDay))")
                }
                if let received = coordinator.lastReceived {
                    LabeledContent("Last received", value: "#\(received.sequence) from \(received.origin.rawValue)")
                }
                if let error = coordinator.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Watch Sync")
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
    NavigationStack {
        WatchSyncStatusView()
    }
}
