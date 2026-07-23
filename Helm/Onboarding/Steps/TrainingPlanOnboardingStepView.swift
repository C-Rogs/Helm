import DesignSystem
import SwiftUI

struct TrainingPlanOnboardingStepView: View {
    var showsFlowControls: Bool = true
    var stepIndex: Int = 4
    var totalSteps: Int = OnboardingStep.allCases.count
    var onContinue: () -> Void = {}
    var onSkip: () -> Void = {}

    @State private var settingsActions: PhaseGoalSettingsActions?

    var body: some View {
        OnboardingStepChrome(
            step: .trainingPlan,
            stepIndex: stepIndex,
            totalSteps: totalSteps,
            showsFlowControls: showsFlowControls,
            primaryTitle: showsFlowControls ? "Continue" : "Done",
            skipTitle: showsFlowControls ? "Set up later" : nil,
            onPrimary: {
                Task {
                    if let settingsActions {
                        guard await settingsActions.saveIfNeeded() else { return }
                    }
                    onContinue()
                }
            },
            onSkip: onSkip
        ) {
            PhaseGoalSettingsView(
                showsInlineSaveButton: false,
                onSaved: showsFlowControls ? onContinue : nil,
                registerActions: { settingsActions = $0 }
            )
        }
    }
}

#Preview {
    TrainingPlanOnboardingStepView()
        .helmTheme()
}
