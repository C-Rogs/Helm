import Core
import SwiftUI

struct WatchBriefView: View {
    let coordinator: WatchSessionCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        List {
            Section {
                arcSection
            } header: {
                Text("Today's ARC")
                    .watchType(.monoTag, color: WatchPalette.fgMuted)
            }
            .listRowBackground(WatchPalette.surface)

            Section {
                briefSection
            } header: {
                Text("Morning brief")
                    .watchType(.monoTag, color: WatchPalette.fgMuted)
            }
            .listRowBackground(WatchPalette.surface)
        }
        .navigationTitle("Brief")
        .helmWatchScreenBackground()
    }

    @ViewBuilder
    private var arcSection: some View {
        if let score = coordinator.latestReadinessScore {
            let state = WatchState.readiness(score: score)
            WatchArcRevealGauge(
                targetValue: Double(score),
                state: state,
                reduceMotion: reduceMotion
            ) { display in
                VStack(spacing: 2) {
                    Text("\(Int(display.rounded()))")
                        .watchType(.heroNumber, color: state.color)
                    Text(state.label)
                        .watchType(.monoTag, color: WatchPalette.fgMuted)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 118)
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("ARC \(score), \(state.label)")
        } else if let error = coordinator.lastError {
            WatchErrorState(title: "ARC unavailable", message: error, retryTitle: nil)
        } else if coordinator.activationState != .activated {
            WatchLoadingState(message: "Connecting")
        } else {
            WatchEmptyState(
                title: "No ARC yet",
                message: "Open Helm on iPhone for your full brief."
            )
        }
    }

    @ViewBuilder
    private var briefSection: some View {
        if let summary = coordinator.latestBriefSummary {
            Text(summary)
                .watchType(.body)
        } else if coordinator.latestReadinessScore == nil, coordinator.lastError != nil {
            EmptyView()
        } else {
            WatchEmptyState(
                title: "No brief yet",
                message: "Open Helm on iPhone for your full brief."
            )
        }
    }
}

#Preview {
    WatchBriefView(coordinator: WatchSessionCoordinator(role: .watch))
        .helmWatchTheme()
}
