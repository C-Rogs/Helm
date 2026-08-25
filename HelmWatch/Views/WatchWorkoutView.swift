import Core
import SwiftUI

struct WatchWorkoutView: View {
    @Bindable var store: WatchWorkoutSessionStore
    var coordinator: WatchSessionCoordinator
    var onRetryStart: (() -> Void)?

    var body: some View {
        Group {
            if coordinator.workoutCompanionActive {
                WatchCompanionView(store: store, coordinator: coordinator, onRetryStart: onRetryStart)
            } else {
                switch store.phase {
                case .idle, .ended:
                    idleView
                case .preparing:
                    WatchLoadingState(message: "Starting")
                case .active, .paused:
                    WatchActiveWorkoutView(store: store)
                case .ending:
                    WatchLoadingState(message: "Saving")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WatchPalette.canvas)
        .task {
            await store.prepareHealthKit()
        }
    }

    private var idleView: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)

            if let error = store.lastError {
                WatchErrorState(message: error, retryTitle: nil)
            } else {
                WatchEmptyState(
                    title: "No session",
                    message: "Start a workout on iPhone to track heart rate here."
                )
            }

            NavigationLink {
                WatchActivityPickerView(store: store)
            } label: {
                Text("Manual workout")
                    .watchType(.label, color: WatchPalette.accent)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
    }
}
