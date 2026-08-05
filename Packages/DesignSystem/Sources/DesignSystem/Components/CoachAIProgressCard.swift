import SwiftUI

/// Coach-styled progress card for vision and other on-device AI pipelines.
public struct CoachAIProgressCard: View {
    private let eyebrow: String
    private let title: String
    private let completedSteps: [String]
    private let currentStep: String
    private let footnote: String?
    private let isImpactful: Bool

    @Environment(\.helmReduceMotion) private var reduceMotion
    @State private var pulsePhase = false

    public init(
        eyebrow: String,
        title: String,
        completedSteps: [String],
        currentStep: String,
        footnote: String? = nil,
        isImpactful: Bool = false
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.completedSteps = completedSteps
        self.currentStep = currentStep
        self.footnote = footnote
        self.isImpactful = isImpactful
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.md) {
            HelmSectionEyebrow(eyebrow)

            Text(title)
                .helmType(.title, color: HelmColor.fg)

            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                ForEach(completedSteps, id: \.self) { step in
                    HStack(spacing: HelmSpacing.sm) {
                        HelmIconView(.checkmark, context: .inline)
                            .foregroundStyle(HelmColor.positive)
                        Text(step)
                            .helmType(.body, color: HelmColor.fg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                HStack(spacing: HelmSpacing.sm) {
                    CoachAIPulseIndicator(isLoading: true)
                    Text(currentStep)
                        .helmType(.body, color: HelmColor.fg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let footnote {
                Text(footnote)
                    .helmType(.body, color: HelmColor.fgSecondary)
            }
        }
        .padding(HelmSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HelmColor.surface, in: RoundedRectangle(cornerRadius: HelmRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: HelmRadius.md)
                .strokeBorder(
                    isImpactful ? HelmColor.accent.opacity(pulsePhase ? 0.65 : 0.25) : HelmColor.hairline,
                    lineWidth: isImpactful ? 1.5 : 1
                )
        }
        .shadow(
            color: isImpactful ? HelmColor.accent.opacity(pulsePhase ? 0.22 : 0.08) : .clear,
            radius: isImpactful ? 12 : 0,
            y: isImpactful ? 4 : 0
        )
        .onAppear {
            guard isImpactful, !reduceMotion else { return }
            withAnimation(HelmMotion.pulseAnimation.repeatForever(autoreverses: true)) {
                pulsePhase = true
            }
        }
    }
}

#if DEBUG
#Preview("Coach AI progress card") {
    CoachAIProgressCard(
        eyebrow: "MEAL VISION",
        title: "Analysing meal",
        completedSteps: ["Reading photo", "Identifying ingredients from photo…"],
        currentStep: "Matching ingredients to CoFID…",
        footnote: "Signal identifies ingredients with vision, then matches each item to CoFID on your phone."
    )
    .helmScreenPadding()
    .padding()
    .helmTheme()
    .helmScreenBackground()
}

#Preview("Coach AI progress impactful") {
    CoachAIProgressCard(
        eyebrow: "COACH",
        title: "Applying change",
        completedSteps: ["Confirmed"],
        currentStep: "Writing to diary…",
        isImpactful: true
    )
    .helmScreenPadding()
    .padding()
    .helmTheme()
    .helmScreenBackground()
}
#endif
