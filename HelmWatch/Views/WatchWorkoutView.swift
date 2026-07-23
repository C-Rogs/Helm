import Core
import SwiftUI

struct WatchWorkoutView: View {
    @Bindable var store: WatchWorkoutSessionStore

    var body: some View {
        Group {
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
        .task {
            await store.prepareHealthKit()
        }
    }

    private var idleView: some View {
        VStack(spacing: 12) {
            NavigationLink {
                WatchActivityPickerView(store: store)
            } label: {
                LabeledContent("Activity", value: store.selectedActivity.displayName)
            }

            if !store.isHealthKitAuthorized {
                Text("HealthKit access required")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Start Workout") {
                Task { await store.startWorkout() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!store.isHealthKitAuthorized)

            if let error = store.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
