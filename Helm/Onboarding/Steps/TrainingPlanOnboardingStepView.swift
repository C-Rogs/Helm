import DesignSystem
import SwiftUI

struct TrainingPlanOnboardingStepView: View {
    var showsFlowControls: Bool = true
    var stepIndex: Int = 4
    var totalSteps: Int = OnboardingStep.allCases.count
    var onContinue: () -> Void = {}
    var onSkip: () -> Void = {}

    var body: some View {
        OnboardingStepChrome(
            step: .trainingPlan,
            stepIndex: stepIndex,
            totalSteps: totalSteps,
            showsFlowControls: showsFlowControls,
            primaryTitle: showsFlowControls ? "Continue" : "Done",
            onPrimary: onContinue,
            onSkip: onSkip
        ) {
            PhaseGoalSettingsView(
                embedInForm: false,
                saveButtonTitle: "Save plan",
                onSaved: showsFlowControls ? onContinue : nil
            )
        }
    }
}

#Preview {
    TrainingPlanOnboardingStepView()
        .helmTheme()
}
