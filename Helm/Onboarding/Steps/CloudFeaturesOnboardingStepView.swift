import DesignSystem
import SwiftUI

struct CloudFeaturesOnboardingStepView: View {
    var stepIndex: Int
    var totalSteps: Int
    var onContinue: () -> Void
    var onBack: (() -> Void)?

    @State private var consent = CloudFeatureConsentPreferences.shared

    var body: some View {
        OnboardingStepChrome(
            step: .cloudFeatures,
            stepIndex: stepIndex,
            totalSteps: totalSteps,
            primaryTitle: "Allow cloud features",
            skipTitle: "Keep features on device",
            onPrimary: {
                consent.accept()
                CoachBootstrap.start()
                onContinue()
            },
            onBack: onBack,
            onSkip: {
                consent.decline()
                onContinue()
            }
        ) {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                cloudRow(
                    title: "Coach",
                    detail: "Chat sends a summary of your readiness, training, nutrition, body data, and coach memory to the coach provider."
                )
                cloudRow(
                    title: "Meal photos",
                    detail: "Photos and any notes go to the meal-vision provider for an estimate."
                )
                cloudRow(
                    title: "Calendar hints",
                    detail: "All-day calendar event titles can go to the coach provider to identify blocked training days."
                )
                cloudRow(
                    title: "Feedback",
                    detail: "Feedback goes to Cam. Coach history is attached only when you enable that option."
                )
                Text("Health import, workout logging, manual nutrition logging, and data export stay on your phone. You can change this later in Settings.")
                    .helmType(.body, color: HelmColor.fgSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(HelmSpacing.md)
            .background(HelmColor.surface, in: RoundedRectangle(cornerRadius: HelmRadius.md))
        }
    }

    private func cloudRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text(title)
                .helmType(.label)
            Text(detail)
                .helmType(.body, color: HelmColor.fgSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    CloudFeaturesOnboardingStepView(
        stepIndex: 4,
        totalSteps: 6,
        onContinue: {},
        onBack: {}
    )
    .helmTheme()
}
