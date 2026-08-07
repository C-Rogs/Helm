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
                    ProgressView("Starting...")
                        .tint(WatchPalette.accent)
                case .active, .paused:
                    WatchActiveWorkoutView(store: store)
                case .ending:
                    ProgressView("Saving...")
                        .tint(WatchPalette.accent)
                }
            }
        }
        .task {
            await store.prepareHealthKit()
        }
    }

    private var idleView: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)

            Text("Start a workout on your iPhone to track heart rate here.")
                .font(WatchType.body.font)
                .foregroundStyle(WatchPalette.fgSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            NavigationLink {
                WatchActivityPickerView(store: store)
            } label: {
                Text("Manual workout")
                    .font(WatchType.label.font)
                    .foregroundStyle(WatchPalette.accent)
            }

            if let error = store.lastError {
                Text(error)
                    .font(WatchType.monoTag.font)
                    .foregroundStyle(WatchPalette.depleted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }
}