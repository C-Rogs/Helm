import SwiftUI

struct WatchCompanionView: View {
    @Bindable var store: WatchWorkoutSessionStore
    let coordinator: WatchSessionCoordinator

    var body: some View {
        VStack(spacing: 10) {
            Text("Phone workout")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let name = coordinator.companionExerciseName {
                Text(name)
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }

            if let setNumber = coordinator.companionSetNumber,
               let setCount = coordinator.companionSetCount {
                Text("Set \(setNumber) of \(setCount)")
                    .font(.caption)
            }

            if let target = coordinator.companionTargetSummary, !target.isEmpty {
                Text(target)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if store.phase == .active || store.phase == .paused {
                WatchActiveWorkoutView(store: store)
            } else if store.isHealthKitAuthorized {
                ProgressView("Starting HR…")
                    .task {
                        await store.startWorkout()
                    }
            } else {
                Text("HealthKit access required")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }
}
