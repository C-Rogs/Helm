import DesignSystem
import SwiftUI

/// Rest + Ask coach chrome pinned to the bottom of Train content.
/// Kept out of `tabViewBottomAccessory`: iOS 26 reserves a tall empty slot there.
struct TrainSessionAccessoryBar: View {
    @Bindable private var controller = TrainBootstrap.sessionController
    @Bindable private var trainPreferences = TrainPreferences.shared
    @State private var didTrackInitialRestRemaining = false

    static func isEnabled(
        selectedTab: AppTab,
        controller: TrainSessionController,
        cardLoggingModeEnabled: Bool
    ) -> Bool {
        guard selectedTab == .train, controller.hasActiveSession, controller.numpadTarget == nil else {
            return false
        }
        let showRest = controller.isRestTimerRunning
            && controller.snapshot?.restTimer?.endsAt != nil
        let showCoach = !controller.isReorderMode && !cardLoggingModeEnabled
        return showRest || showCoach
    }

    var body: some View {
        let showRest = controller.isRestTimerRunning
            && controller.snapshot?.restTimer?.endsAt != nil
        let showCoach = !controller.isReorderMode
            && !trainPreferences.cardLoggingModeEnabled

        VStack(spacing: HelmSpacing.xs) {
            if showRest,
               let timer = controller.snapshot?.restTimer,
               let endsAt = timer.endsAt {
                RestTimerBanner(
                    endsAt: endsAt,
                    totalSeconds: controller.restTimerTotalSeconds(for: timer),
                    onSkip: {
                        Task { @MainActor in await controller.skipRest() }
                    },
                    onAdjust: { delta in
                        Task { @MainActor in await controller.adjustRestTimer(deltaSeconds: delta) }
                    },
                    onRemainingSecondsChange: forwardRestTick,
                    upNextName: controller.upNextExerciseName
                )
            }

            if showCoach {
                coachBar
            }
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, HelmSpacing.xxs)
    }

    private var coachBar: some View {
        let restTimer = controller.snapshot?.restTimer
        let bar = AskCoachBar(
            prompt: controller.isCoachThinking ? "Coach thinking" : "Ask coach",
            peekSnippet: ProactiveCoachPreferences.peekEnabled ? controller.coachPeekSnippet : nil,
            isLoading: controller.isCoachThinking
        ) {
            controller.isShowingCoachPrompt = true
        }

        return Group {
            if trainPreferences.manualRestTimerEnabled {
                HStack(spacing: HelmSpacing.xs) {
                    bar
                        .layoutPriority(1)

                    ManualRestTimerPill(
                        isRunning: controller.isRestTimerRunning,
                        endsAt: restTimer?.endsAt
                    ) {
                        controller.openManualRestTimer(expanded: controller.isRestTimerRunning)
                    }
                    .fixedSize()
                }
                .padding(.horizontal, HelmSpacing.screenGutter)
                .padding(.bottom, HelmSpacing.xs)
            } else {
                bar
                    .padding(.horizontal, HelmSpacing.screenGutter)
                    .padding(.bottom, HelmSpacing.xs)
            }
        }
    }

    private func forwardRestTick(_ remaining: Int) {
        if !didTrackInitialRestRemaining {
            didTrackInitialRestRemaining = true
            controller.handleRestRemainingSecondsChange(remaining > 0 ? remaining : 0)
            return
        }
        controller.handleRestRemainingSecondsChange(remaining)
    }
}
