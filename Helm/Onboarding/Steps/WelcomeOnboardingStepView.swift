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
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text("ARC")
                            .helmType(.monoTag, color: HelmColor.fgMuted)
                            .lineLimit(1)
                    }
                    // Keeps the word inside the arc interior; hero type is sized for digits.
                    .frame(maxWidth: 132)
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
