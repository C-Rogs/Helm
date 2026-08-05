import DesignSystem
import SwiftUI

struct BodyProfileOnboardingStepView: View {
    var showsFlowControls: Bool = true
    var stepIndex: Int = 3
    var totalSteps: Int = OnboardingStep.allCases.count
    var onContinue: () -> Void = {}
    var onBack: (() -> Void)? = nil
    var onSkip: () -> Void = {}

    @State private var settingsActions: BodyProfileSettingsActions?
    @State private var isLoadingProfile = true

    var body: some View {
        OnboardingStepChrome(
            step: .bodyProfile,
            stepIndex: stepIndex,
            totalSteps: totalSteps,
            showsFlowControls: showsFlowControls,
            primaryTitle: showsFlowControls ? "Continue" : "Done",
            isPrimaryLoading: isLoadingProfile,
            skipTitle: showsFlowControls ? "Set up later" : nil,
            onPrimary: {
                Task {
                    if let settingsActions {
                        guard await settingsActions.saveIfNeeded() else { return }
                        guard settingsActions.isValid() else { return }
                    }
                    onContinue()
                }
            },
            onBack: onBack,
            onSkip: onSkip
        ) {
            BodyProfileSettingsView(
                embedInForm: false,
                showsInlineSaveButton: false,
                onSaved: showsFlowControls ? onContinue : nil,
                registerActions: { settingsActions = $0 },
                onLoadingChanged: { isLoadingProfile = $0 }
            )
        }
    }
}

#Preview {
    BodyProfileOnboardingStepView()
        .helmTheme()
}
