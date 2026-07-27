import DesignSystem
import SwiftUI

struct OnboardingStepChrome<Content: View>: View {
    let step: OnboardingStep
    let stepIndex: Int
    let totalSteps: Int
    let showsFlowControls: Bool
    let primaryTitle: String
    let skipTitle: String?
    let onPrimary: () -> Void
    let onBack: (() -> Void)?
    let onSkip: () -> Void
    @ViewBuilder var content: () -> Content

    init(
        step: OnboardingStep,
        stepIndex: Int,
        totalSteps: Int,
        showsFlowControls: Bool = true,
        primaryTitle: String = "Continue",
        skipTitle: String? = "Skip for now",
        onPrimary: @escaping () -> Void,
        onBack: (() -> Void)? = nil,
        onSkip: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.step = step
        self.stepIndex = stepIndex
        self.totalSteps = totalSteps
        self.showsFlowControls = showsFlowControls
        self.primaryTitle = primaryTitle
        self.skipTitle = skipTitle
        self.onPrimary = onPrimary
        self.onBack = onBack
        self.onSkip = onSkip
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                if showsFlowControls {
                    Text("Step \(stepIndex) of \(totalSteps)")
                        .font(HelmTypography.monoTag)
                        .foregroundStyle(HelmColor.fgMuted)
                        .textCase(.uppercase)
                }

                VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                    Text(step.title)
                        .font(HelmTypography.title)
                        .foregroundStyle(HelmColor.fg)

                    Text(step.subtitle)
                        .font(HelmTypography.body)
                        .foregroundStyle(HelmColor.fgSecondary)
                }

                content()

                if showsFlowControls {
                    VStack(spacing: HelmSpacing.sm) {
                        Button(primaryTitle) {
                            HapticEngine.shared.play(.selection)
                            onPrimary()
                        }
                        .buttonStyle(.helmPrimary)

                        if let onBack {
                            Button("Back") {
                                HapticEngine.shared.play(.selection)
                                onBack()
                            }
                            .buttonStyle(.helmSecondary)
                        }

                        if step != .shortcuts, let skipTitle {
                            Button(skipTitle) {
                                HapticEngine.shared.play(.selection)
                                onSkip()
                            }
                            .buttonStyle(.helmSecondary)
                        }
                    }
                }
            }
            .padding(HelmSpacing.lg)
        }
        .helmScreenBackground()
    }
}
