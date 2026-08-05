import DesignSystem
import SwiftUI

struct OnboardingStepChrome<Content: View>: View {
    let step: OnboardingStep
    let stepIndex: Int
    let totalSteps: Int
    let showsFlowControls: Bool
    let primaryTitle: String
    let isPrimaryLoading: Bool
    /// Only set on steps whose primary action can be blocked by validation. Elsewhere
    /// Continue already advances without side effects, so a skip button is redundant.
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
        isPrimaryLoading: Bool = false,
        skipTitle: String? = nil,
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
        self.isPrimaryLoading = isPrimaryLoading
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
                        Button {
                            HapticEngine.shared.play(.selection)
                            onPrimary()
                        } label: {
                            if isPrimaryLoading {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(HelmColor.buttonPrimaryForeground)
                                    .accessibilityLabel("Loading")
                            } else {
                                Text(primaryTitle)
                            }
                        }
                        .buttonStyle(.helmPrimary)
                        .disabled(isPrimaryLoading)
                        .opacity(isPrimaryLoading ? 0.65 : 1)

                        if let onBack {
                            Button("Back") {
                                HapticEngine.shared.play(.selection)
                                onBack()
                            }
                            .buttonStyle(.helmSecondary)
                        }

                        if let skipTitle {
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
