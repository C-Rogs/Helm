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
            onPrimary: onContinue,
            onSkip: onSkip
        ) {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                Text("Create a personal automation in Shortcuts to generate your morning brief when you dismiss your alarm or unlock your phone.")
                    .font(HelmTypography.body)
                    .foregroundStyle(HelmColor.fgSecondary)

                Text("A full setup guide will appear in Settings soon. For now, open Shortcuts and add the Helm brief action when you are ready.")
                    .font(HelmTypography.caption)
                    .foregroundStyle(HelmColor.fgMuted)

                Button("Open Shortcuts") {
                    openShortcuts()
                }
                .buttonStyle(.helmSecondary)
            }
            .padding(HelmSpacing.md)
            .background(HelmColor.surface, in: RoundedRectangle(cornerRadius: HelmRadius.md))
        }
    }

    private func openShortcuts() {
        guard let url = URL(string: "shortcuts://") else { return }
        UIApplication.shared.open(url)
        HapticEngine.shared.play(.selection)
    }
}

#Preview {
    ShortcutsOnboardingStepView()
        .helmTheme()
}
