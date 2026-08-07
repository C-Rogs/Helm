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
                    .font(WatchType.title.font)
                    .foregroundStyle(WatchPalette.fg)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }

            if let setNumber = coordinator.companionSetNumber,
               let setCount = coordinator.companionSetCount {
                Text("Set \(setNumber) of \(setCount)")
                    .font(WatchType.monoTag.font)
                    .foregroundStyle(WatchPalette.fgSecondary)
            }

            if let target = coordinator.companionTargetSummary, !target.isEmpty {
                Text(target)
                    .font(WatchType.body.font)
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
                .font(WatchType.monoTag.font)
                .foregroundStyle(WatchPalette.fgMuted)
            Spacer(minLength: 0)
            if store.phase == .active || store.phase == .paused {
                Text(elapsedLabel)
                    .font(WatchType.monoTag.font)
                    .foregroundStyle(WatchPalette.fgMuted)
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
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let bpm = store.heartRateBPM {
                    Text("\(Int(bpm.rounded()))")
                        .font(WatchType.bigNumber.font)
                        .foregroundStyle(WatchZoneColor.color(for: store.heartRateZone))
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(WatchZoneColor.color(for: store.heartRateZone))
                    if let zone = store.heartRateZone {
                        Text(zone.displayName)
                            .font(WatchType.monoTag.font)
                            .foregroundStyle(WatchZoneColor.color(for: store.heartRateZone))
                    }
                } else {
                    Text("--")
                        .font(WatchType.bigNumber.font)
                        .foregroundStyle(WatchPalette.fgSecondary)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(WatchPalette.fgMuted)
                }
            }
            .padding(.vertical, 2)
        case .preparing:
            ProgressView("Starting HR...")
                .controlSize(.mini)
                .tint(WatchPalette.accent)
        case .ending:
            ProgressView("Ending...")
                .controlSize(.mini)
                .tint(WatchPalette.accent)
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
                .font(WatchType.monoTag.font)
                .foregroundStyle(WatchPalette.fgMuted)
                .multilineTextAlignment(.center)
        } else if !coordinator.isReachable {
            Text("Reconnect phone to complete set")
                .font(WatchType.monoTag.font)
                .foregroundStyle(WatchPalette.fgSecondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var idleOrFailedBody: some View {
        if !store.isHealthKitAuthorized {
            Text("HealthKit access required")
                .font(WatchType.body.font)
                .foregroundStyle(WatchPalette.fgSecondary)
        } else if let error = store.lastError {
            VStack(spacing: 4) {
                Text(error)
                    .font(WatchType.body.font)
                    .foregroundStyle(WatchPalette.depleted)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                Button("Retry") {
                    onRetryStart?()
                }
                .font(WatchType.label.font)
                .tint(WatchPalette.accent)
            }
        } else if store.phase == .ended {
            Text("Ended. Keep phone workout open.")
                .font(WatchType.body.font)
                .foregroundStyle(WatchPalette.fgSecondary)
                .multilineTextAlignment(.center)
        } else {
            ProgressView("Starting HR...")
                .controlSize(.mini)
                .tint(WatchPalette.accent)
        }
    }

    private var elapsedLabel: String {
        let minutes = store.elapsedSeconds / 60
        let seconds = store.elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}