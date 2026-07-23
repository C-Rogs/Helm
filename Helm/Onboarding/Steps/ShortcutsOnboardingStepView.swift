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
                Text("Helm will appear in Shortcuts after the morning-brief automation feature ships.")
                    .font(HelmTypography.body)
                    .foregroundStyle(HelmColor.fgSecondary)

                Text("For now, open Helm each morning for your brief on the Dashboard. A setup guide is in Settings under Morning Brief Automation.")
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
