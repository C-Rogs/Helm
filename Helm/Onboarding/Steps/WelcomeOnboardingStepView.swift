import DesignSystem
import SwiftUI

struct WelcomeOnboardingStepView: View {
    var showsFlowControls: Bool = true
    var stepIndex: Int = 1
    var totalSteps: Int = OnboardingStep.allCases.count
    var onContinue: () -> Void = {}
    var onBack: (() -> Void)? = nil
    var onSkip: () -> Void = {}

    @Environment(\.helmReduceMotion) private var reduceMotion

    var body: some View {
        OnboardingStepChrome(
            step: .welcome,
            stepIndex: stepIndex,
            totalSteps: totalSteps,
            showsFlowControls: showsFlowControls,
            onPrimary: onContinue,
            onBack: onBack,
            onSkip: onSkip
        ) {
            VStack(spacing: HelmSpacing.lg) {
                ArcDrawGauge(targetValue: 72, state: .ready, reduceMotion: reduceMotion) {
                    VStack(spacing: HelmSpacing.xxs) {
                        Text("Signal")
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
