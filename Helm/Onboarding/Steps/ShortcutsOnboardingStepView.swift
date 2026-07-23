import DesignSystem
import SwiftUI

struct ShortcutsOnboardingStepView: View {
    var showsFlowControls: Bool = true
    var stepIndex: Int = 6
    var totalSteps: Int = OnboardingStep.allCases.count
    var onContinue: () -> Void = {}
    var onSkip: () -> Void = {}

    var body: some View {
        OnboardingStepChrome(
            step: .shortcuts,
            stepIndex: stepIndex,
            totalSteps: totalSteps,
            showsFlowControls: showsFlowControls,
            primaryTitle: "Get started",
            skipTitle: nil,
            onPrimary: onContinue,
            onSkip: onSkip
        ) {
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

#Preview {
    NavigationStack {
        ShortcutsOnboardingStepView()
    }
    .helmTheme()
}
