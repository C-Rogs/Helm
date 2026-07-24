import DesignSystem
import SwiftUI

struct OnboardingFlowView: View {
    let onFinished: () -> Void

    @State private var coordinator = OnboardingCoordinator()

    private let totalSteps = OnboardingStep.allCases.count

    var body: some View {
        NavigationStack {
            stepView(for: coordinator.currentStep)
                .navigationBarTitleDisplayMode(.inline)
        }
        .helmTheme()
    }

    @ViewBuilder
    private func stepView(for step: OnboardingStep) -> some View {
        let stepIndex = step.rawValue + 1
        let advance = { coordinator.advance() }
        let skip = { coordinator.skip() }
        let finish = {
            OnboardingStore.shared.markCompleted()
            HealthKitBootstrap.startAfterOnboarding()
            onFinished()
        }

        switch step {
        case .welcome:
            WelcomeOnboardingStepView(
                stepIndex: stepIndex,
                totalSteps: totalSteps,
                onContinue: advance,
                onSkip: skip
            )
        case .healthKit:
            HealthKitOnboardingStepView(
                stepIndex: stepIndex,
                totalSteps: totalSteps,
                onContinue: advance,
                onSkip: skip
            )
        case .notifications:
            NotificationOnboardingStepView(
                stepIndex: stepIndex,
                totalSteps: totalSteps,
                onContinue: advance,
                onSkip: skip
            )
        case .coachKey:
            CoachKeyOnboardingStepView(
                stepIndex: stepIndex,
                totalSteps: totalSteps,
                onContinue: advance,
                onSkip: skip
            )
        case .trainingPlan:
            TrainingPlanOnboardingStepView(
                stepIndex: stepIndex,
                totalSteps: totalSteps,
                onContinue: advance,
                onSkip: skip
            )
        case .backfill:
            BackfillOnboardingStepView(
                stepIndex: stepIndex,
                totalSteps: totalSteps,
                onContinue: advance,
                onSkip: skip
            )
        case .shortcuts:
            ShortcutsOnboardingStepView(
                stepIndex: stepIndex,
                totalSteps: totalSteps,
                onContinue: finish,
                onSkip: finish
            )
        }
    }
}

#Preview {
    OnboardingFlowView(onFinished: {})
}
