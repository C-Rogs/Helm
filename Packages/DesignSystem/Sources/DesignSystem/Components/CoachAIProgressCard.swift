import SwiftUI

/// Coach-styled progress card for vision and other on-device AI pipelines.
public struct CoachAIProgressCard: View {
    private let eyebrow: String
    private let title: String
    private let completedSteps: [String]
    private let currentStep: String
    private let footnote: String?

    public init(
        eyebrow: String,
        title: String,
        completedSteps: [String],
        currentStep: String,
        footnote: String? = nil
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.completedSteps = completedSteps
        self.currentStep = currentStep
        self.footnote = footnote
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
                .strokeBorder(HelmColor.hairline, lineWidth: 1)
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
        footnote: "Helm identifies ingredients with vision, then matches each item to CoFID on your phone."
    )
    .helmScreenPadding()
    .padding()
    .helmTheme()
    .helmScreenBackground()
}
#endif
