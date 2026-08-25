import Core
import SwiftUI
import WatchKit

struct WatchCompanionView: View {
    @Bindable var store: WatchWorkoutSessionStore
    let coordinator: WatchSessionCoordinator
    var onRetryStart: (() -> Void)?

    var body: some View {
        VStack(spacing: 4) {
            linkRow

            if let name = coordinator.companionExerciseName {
                Text(name)
                    .watchType(.title)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }

            if let setNumber = coordinator.companionSetNumber,
               let setCount = coordinator.companionSetCount {
                Text("Set \(setNumber) of \(setCount)")
                    .watchType(.monoTag, color: WatchPalette.fgSecondary)
            }

            if let target = coordinator.companionTargetSummary, !target.isEmpty {
                Text(target)
                    .font(WatchType.number.font)
                    .foregroundStyle(WatchPalette.fgSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }

            companionMetrics

            Spacer(minLength: 0)

            doneButton

            statusFooter
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .frame(maxHeight: .infinity)
    }

    private var linkRow: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(linkColor)
                .frame(width: 6, height: 6)
            Text(linkLabel)
                .watchType(.monoTag, color: WatchPalette.fgMuted)
            Spacer(minLength: 0)
            if store.phase == .active || store.phase == .paused {
                Text(elapsedLabel)
                    .watchType(.number, color: WatchPalette.fgMuted)
            }
        }
    }

    private var linkLabel: String {
        coordinator.isReachable ? "Live" : "Reconnect"
    }

    private var linkColor: Color {
        coordinator.isReachable ? WatchPalette.accent : WatchPalette.compromised
    }

    @ViewBuilder
    private var companionMetrics: some View {
        switch store.phase {
        case .active, .paused:
            let zone = store.heartRateZone
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let bpm = store.heartRateBPM {
                    Text("\(Int(bpm.rounded()))")
                        .watchType(.bigNumber, color: WatchZoneColor.color(for: zone))
                    Text(zone?.displayName ?? "BPM")
                        .watchType(.monoTag, color: WatchZoneColor.color(for: zone))
                } else {
                    Text("--")
                        .watchType(.bigNumber, color: WatchPalette.fgSecondary)
                    Text("HR")
                        .watchType(.monoTag, color: WatchPalette.fgMuted)
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        case .preparing:
            WatchLoadingState(message: "Starting HR")
        case .ending:
            WatchLoadingState(message: "Ending")
        case .idle, .ended:
            idleOrFailedBody
        }
    }

    @ViewBuilder
    private var doneButton: some View {
        let setID = coordinator.companionSetID
        let isPending = setID.map { coordinator.pendingCompleteSetIDs.contains($0) } ?? false
        let canComplete = coordinator.companionSessionExerciseID != nil
            && setID != nil
            && (store.phase == .active || store.phase == .paused)
            && !isPending

        Button {
            guard
                let exerciseID = coordinator.companionSessionExerciseID,
                let setID
            else { return }
            coordinator.requestCompleteSet(sessionExerciseID: exerciseID, setID: setID)
            WKInterfaceDevice.current().play(.click)
        } label: {
            Text(isPending ? "Sending..." : "Done")
                .font(WatchType.label.font)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(WatchPalette.accent)
        .foregroundStyle(WatchPalette.buttonPrimaryForeground)
        .disabled(!canComplete)
        .opacity(canComplete ? 1 : 0.45)
    }

    @ViewBuilder
    private var statusFooter: some View {
        if let setID = coordinator.companionSetID,
           coordinator.pendingCompleteSetIDs.contains(setID) {
            Text(coordinator.isReachable ? "Sending..." : "Queued for phone")
                .watchType(.monoTag, color: WatchPalette.fgMuted)
                .multilineTextAlignment(.center)
        } else if !coordinator.isReachable {
            Text("Reconnect phone to complete set")
                .watchType(.monoTag, color: WatchPalette.fgSecondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var idleOrFailedBody: some View {
        if !store.isHealthKitAuthorized {
            WatchErrorState(
                title: "HealthKit required",
                message: "Allow heart rate on this Watch.",
                retryTitle: nil
            )
        } else if let error = store.lastError {
            WatchErrorState(message: error) {
                onRetryStart?()
            }
        } else if store.phase == .ended {
            WatchEmptyState(
                title: "Ended",
                message: "Keep the phone workout open."
            )
        } else {
            WatchLoadingState(message: "Starting HR")
        }
    }

    private var elapsedLabel: String {
        let minutes = store.elapsedSeconds / 60
        let seconds = store.elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
