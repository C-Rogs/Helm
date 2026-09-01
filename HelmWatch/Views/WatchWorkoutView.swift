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
        VStack(spacing: WatchSpacing.xs) {
            Spacer(minLength: 0)

            if let error = store.lastError {
                WatchErrorState(message: error, retryTitle: nil)
            } else {
                WatchEmptyState(
                    title: "Ready",
                    message: "Start Train on iPhone for sets. Manual is HR only."
                )
            }

            NavigationLink {
                WatchActivityPickerView(store: store)
            } label: {
                Text("Manual")
                    .watchType(.label, color: WatchPalette.buttonPrimaryForeground)
                    .frame(maxWidth: .infinity, minHeight: WatchLayout.hit)
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchPalette.accent)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, WatchSpacing.xs)
        .frame(maxHeight: .infinity)
    }
}
