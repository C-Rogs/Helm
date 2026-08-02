import Core
import SwiftUI
import WatchKit

struct WatchCompanionView: View {
    @Bindable var store: WatchWorkoutSessionStore
    let coordinator: WatchSessionCoordinator
    var onRetryStart: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Circle()
                    .fill(linkColor)
                    .frame(width: 6, height: 6)
                Text(linkLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

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

            doneButton

            companionSessionBody
        }
        .padding(.horizontal, 4)
    }

    private var linkLabel: String {
        coordinator.isReachable ? "Live" : "Reconnect"
    }

    private var linkColor: Color {
        coordinator.isReachable ? .green : .orange
    }

    @ViewBuilder
    private var doneButton: some View {
        let canComplete = coordinator.isReachable
            && coordinator.companionSessionExerciseID != nil
            && coordinator.companionSetID != nil
            && (store.phase == .active || store.phase == .paused)

        Button("Done") {
            guard
                let exerciseID = coordinator.companionSessionExerciseID,
                let setID = coordinator.companionSetID
            else { return }
            coordinator.requestCompleteSet(sessionExerciseID: exerciseID, setID: setID)
            WKInterfaceDevice.current().play(.click)
        }
        .font(.headline)
        .disabled(!canComplete)
        .opacity(canComplete ? 1 : 0.4)

        if !coordinator.isReachable {
            Text("Reconnect phone to complete set")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var companionSessionBody: some View {
        switch store.phase {
        case .active, .paused:
            WatchActiveWorkoutView(store: store)
        case .preparing:
            ProgressView("Starting HR…")
        case .ending:
            ProgressView("Ending…")
        case .idle, .ended:
            idleOrFailedBody
        }
    }

    @ViewBuilder
    private var idleOrFailedBody: some View {
        if !store.isHealthKitAuthorized {
            Text("HealthKit access required")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if let error = store.lastError {
            VStack(spacing: 4) {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                Button("Retry") {
                    onRetryStart?()
                }
                .font(.caption)
            }
        } else if store.phase == .ended {
            Text("Ended. Keep phone workout open.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else {
            ProgressView("Starting HR…")
        }
    }
}
