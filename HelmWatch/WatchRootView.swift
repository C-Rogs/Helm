import Core
import SwiftUI

struct WatchRootView: View {
    @State private var coordinator = WatchSessionCoordinator(role: .watch)
    @State private var workoutStore = WatchWorkoutSessionStore()

    var body: some View {
        TabView {
            WatchWorkoutView(store: workoutStore)
                .tabItem {
                    Label("Workout", systemImage: "heart.fill")
                }

            syncStatusTab
                .tabItem {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
        }
    }

    private var syncStatusTab: some View {
        List {
            Section("Helm") {
                Text("Watch skeleton")
                    .font(.headline)
                if let received = coordinator.lastReceived {
                    LabeledContent("Phone day", value: received.helmDay)
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
