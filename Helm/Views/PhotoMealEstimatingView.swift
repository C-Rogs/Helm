import DesignSystem
import SwiftUI

struct PhotoMealEstimatingView: View {
    let previewImage: UIImage?
    let completedSteps: [String]
    let currentStep: String
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                backdrop

                ScrollView {
                    CoachAIProgressCard(
                        eyebrow: "MEAL VISION",
                        title: "Analysing meal",
                        completedSteps: completedSteps,
                        currentStep: currentStep,
                        footnote: "Helm identifies ingredients with vision, then matches each item to CoFID on your phone."
                    )
                    .helmScreenPadding()
                    .padding(.top, HelmSpacing.xl)
                    .padding(.bottom, HelmSpacing.lg)
                }
            }
            .helmScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .interactiveDismissDisabled()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Analysing meal photo")
    }

    private var backdrop: some View {
        ZStack {
            HelmColor.canvas
                .ignoresSafeArea()

            if let previewImage {
                GeometryReader { geometry in
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .opacity(0.35)
                }
                .ignoresSafeArea()
            }

            HelmColor.canvas.opacity(0.72)
                .ignoresSafeArea()
        }
    }
}

#Preview("Photo estimating") {
    PhotoMealEstimatingView(
        previewImage: nil,
        completedSteps: ["Reading photo", "Identifying ingredients from photo…"],
        currentStep: "Matching ingredients to CoFID…",
        onCancel: {}
    )
    .helmTheme()
}
