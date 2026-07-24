import DesignSystem
import SwiftUI

struct WelcomeOnboardingStepView: View {
    var showsFlowControls: Bool = true
    var stepIndex: Int = 1
    var totalSteps: Int = OnboardingStep.allCases.count
    var onContinue: () -> Void = {}
    var onSkip: () -> Void = {}

    @Environment(\.helmReduceMotion) private var reduceMotion

    var body: some View {
        OnboardingStepChrome(
            step: .welcome,
            stepIndex: stepIndex,
            totalSteps: totalSteps,
            showsFlowControls: showsFlowControls,
            onPrimary: onContinue,
            onSkip: onSkip
        ) {
            VStack(spacing: HelmSpacing.lg) {
                ArcDrawGauge(targetValue: 72, state: .ready, reduceMotion: reduceMotion) {
                    VStack(spacing: HelmSpacing.xxs) {
                        Text("Helm")
                            .helmType(.heroNumber)
                        Text("ARC")
                            .helmType(.monoTag, color: HelmColor.fgMuted)
                    }
                }
                .frame(maxWidth: 220)
                .frame(maxWidth: .infinity)

                Text("Readiness, training, and nutrition in one calm instrument.")
                    .font(HelmTypography.body)
                    .foregroundStyle(HelmColor.fgSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(HelmSpacing.md)
            .background(HelmColor.surface, in: RoundedRectangle(cornerRadius: HelmRadius.md))
        }
    }
}

#Preview {
    WelcomeOnboardingStepView()
        .helmTheme()
}
