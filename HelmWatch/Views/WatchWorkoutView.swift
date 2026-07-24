import Core
import SwiftUI

struct WatchWorkoutView: View {
    @Bindable var store: WatchWorkoutSessionStore
    var coordinator: WatchSessionCoordinator

    var body: some View {
        Group {
            if coordinator.workoutCompanionActive {
                WatchCompanionView(store: store, coordinator: coordinator)
            } else {
                switch store.phase {
                case .idle, .ended:
                    idleView
                case .preparing:
                    ProgressView("Starting…")
                case .active, .paused:
                    WatchActiveWorkoutView(store: store)
                case .ending:
                    ProgressView("Saving…")
                }
            }
        }
        .task {
            await store.prepareHealthKit()
        }
    }

    private var idleView: some View {
        VStack(spacing: 12) {
            Text("Start a workout on your iPhone to track heart rate here.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            NavigationLink {
                WatchActivityPickerView(store: store)
            } label: {
                Text("Manual workout")
                    .font(.caption)
            }

            if let error = store.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
