import Core
import SwiftUI
import WatchKit

struct WatchCompanionView: View {
    @Bindable var store: WatchWorkoutSessionStore
    let coordinator: WatchSessionCoordinator
    var onRetryStart: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                linkRow

                if let name = coordinator.companionExerciseName {
                    Text(name)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }

                if let setNumber = coordinator.companionSetNumber,
                   let setCount = coordinator.companionSetCount {
                    Text("Set \(setNumber) of \(setCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let target = coordinator.companionTargetSummary, !target.isEmpty {
                    Text(target)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                companionMetrics

                doneButton

                if !coordinator.isReachable {
                    Text("Reconnect phone to complete set")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
    }

    private var linkRow: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(linkColor)
                .frame(width: 6, height: 6)
            Text(linkLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if store.phase == .active || store.phase == .paused {
                Text(elapsedLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var linkLabel: String {
        coordinator.isReachable ? "Live" : "Reconnect"
    }

    private var linkColor: Color {
        coordinator.isReachable ? .green : .orange
    }

    @ViewBuilder
    private var companionMetrics: some View {
        switch store.phase {
        case .active, .paused:
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let bpm = store.heartRateBPM {
                    Text("\(Int(bpm.rounded()))")
                        .font(.title.bold().monospacedDigit())
                        .foregroundStyle(zoneColor)
                    Text("BPM")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let zone = store.heartRateZone {
                        Text(zone.displayName)
                            .font(.caption2)
                            .foregroundStyle(zoneColor)
                    }
                } else {
                    Text("--")
                        .font(.title.bold().monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("BPM")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        case .preparing:
            ProgressView("Starting HR…")
                .controlSize(.mini)
        case .ending:
            ProgressView("Ending…")
                .controlSize(.mini)
        case .idle, .ended:
            idleOrFailedBody
        }
    }

    @ViewBuilder
    private var doneButton: some View {
        // Reachability optional: transferUserInfo queues when phone briefly unreachable.
        let canComplete = coordinator.companionSessionExerciseID != nil
            && coordinator.companionSetID != nil
            && (store.phase == .active || store.phase == .paused)

        Button {
            guard
                let exerciseID = coordinator.companionSessionExerciseID,
                let setID = coordinator.companionSetID
            else { return }
            coordinator.requestCompleteSet(sessionExerciseID: exerciseID, setID: setID)
            WKInterfaceDevice.current().play(.click)
        } label: {
            Text("Done")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .disabled(!canComplete)
        .opacity(canComplete ? 1 : 0.45)
        .padding(.top, 2)
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
                .controlSize(.mini)
        }
    }

    private var elapsedLabel: String {
        let minutes = store.elapsedSeconds / 60
        let seconds = store.elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var zoneColor: Color {
        switch store.heartRateZone {
        case .zone1: .mint
        case .zone2: .blue
        case .zone3: .yellow
        case .zone4: .orange
        case .zone5: .red
        case nil: .primary
        }
    }
}
