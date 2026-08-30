import DesignSystem
import SwiftUI

struct TrainingPlanOnboardingStepView: View {
    var stepIndex: Int = 5
    var totalSteps: Int = OnboardingStep.allCases.count
    var onContinue: () -> Void = {}
    var onBack: (() -> Void)? = nil
    var onSkip: () -> Void = {}

    var body: some View {
        PlanBuilderFlowView(
            presentation: .onboarding(
                stepIndex: stepIndex,
                totalSteps: totalSteps,
                onSkip: onSkip
            ),
            hidesMaintenanceField: true,
            onFinished: onContinue
        )
    }
}

#Preview {
    TrainingPlanOnboardingStepView()
        .helmTheme()
}
