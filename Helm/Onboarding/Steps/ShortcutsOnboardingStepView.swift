import DesignSystem
import HealthKitIngest
import ReadinessKit
import SwiftUI

struct ShortcutsOnboardingStepView: View {
    var showsFlowControls: Bool = true
    var stepIndex: Int = 7
    var totalSteps: Int = OnboardingStep.allCases.count
    var onContinue: () -> Void = {}
    var onBack: (() -> Void)? = nil
    var onSkip: () -> Void = {}

    @Environment(\.helmReduceMotion) private var reduceMotion
    @State private var revealDetailsVisible = false

    private var readinessScore: ReadinessScore? {
        if case let .scored(score) = ReadinessBootstrap.readinessService.state {
            return score
        }
        return nil
    }

    var body: some View {
        OnboardingStepChrome(
            step: .shortcuts,
            stepIndex: stepIndex,
            totalSteps: totalSteps,
            showsFlowControls: showsFlowControls,
            primaryTitle: "Get started",
            skipTitle: nil,
            onPrimary: onContinue,
            onBack: onBack,
            onSkip: onSkip
        ) {
            VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                payoffSection

                VStack(alignment: .leading, spacing: HelmSpacing.md) {
                    Text("Helm is available in Shortcuts. Set up a morning automation so your brief generates when you dismiss your alarm or unlock your phone.")
                        .font(HelmTypography.body)
                        .foregroundStyle(HelmColor.fgSecondary)

                    Text("Pre-workout and post-workout notifications work automatically once notifications are enabled.")
                        .font(HelmTypography.caption)
                        .foregroundStyle(HelmColor.fgMuted)

                    NavigationLink("View setup guide") {
                        MorningBriefAutomationGuideView()
                    }
                    .buttonStyle(.helmSecondary)
                }
                .padding(HelmSpacing.md)
                .background(HelmColor.surface, in: RoundedRectangle(cornerRadius: HelmRadius.md))
            }
        }
    }

    @ViewBuilder
    private var payoffSection: some View {
        if let score = readinessScore {
            let helmState = HelmState.readiness(score: Double(score.score))
            VStack(spacing: HelmSpacing.md) {
                Text("Your first readiness score")
                    .font(HelmTypography.headline)
                    .foregroundStyle(HelmColor.fg)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ArcRevealGauge(
                    targetValue: Double(score.score),
                    state: helmState,
                    reveal: true,
                    reduceMotion: reduceMotion,
                    detailsVisible: $revealDetailsVisible,
                    onRevealStart: {
                        HapticEngine.shared.play(.readinessReveal)
                    }
                ) { displayValue in
                    VStack(spacing: HelmSpacing.xxs) {
                        HelmNumericText(Int(displayValue.rounded()))
                            .helmType(.heroNumber, color: HelmColor.color(for: helmState))
                        Text(helmState.label)
                            .helmType(.monoTag, color: HelmColor.fgMuted)
                    }
                }
                .frame(maxWidth: 200)
                .frame(maxWidth: .infinity)
            }
            .padding(HelmSpacing.md)
            .background(HelmColor.surface, in: RoundedRectangle(cornerRadius: HelmRadius.md))
        }
    }
}

#Preview {
    NavigationStack {
        ShortcutsOnboardingStepView()
    }
    .helmTheme()
}
