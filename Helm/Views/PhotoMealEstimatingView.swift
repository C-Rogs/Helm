import DesignSystem
import SwiftUI

struct PhotoMealEstimatingView: View {
    let previewImage: UIImage?
    let completedSteps: [String]
    let currentStep: String
    let usesLidarAssist: Bool
    let onCancel: () -> Void

    private var footnote: String {
        if usesLidarAssist {
            return "Helm used LiDAR depth from your camera to refine portion size, then identifies ingredients with vision and matches each item to CoFID on your phone."
        }
        return "Helm identifies ingredients with vision, then matches each item to CoFID on your phone."
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backdrop

                ScrollView {
                    CoachAIProgressCard(
                        eyebrow: usesLidarAssist ? "MEAL VISION · LIDAR" : "MEAL VISION",
                        title: "Analysing meal",
                        completedSteps: completedSteps,
                        currentStep: currentStep,
                        footnote: footnote
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
        .accessibilityLabel(usesLidarAssist ? "Analysing meal photo with LiDAR portion assist" : "Analysing meal photo")
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
        usesLidarAssist: false,
        onCancel: {}
    )
    .helmTheme()
}

#Preview("Photo estimating with LiDAR") {
    PhotoMealEstimatingView(
        previewImage: nil,
        completedSteps: [
            "Reading photo with LiDAR depth…",
            "Applying LiDAR depth to portion scale…"
        ],
        currentStep: "Identifying ingredients from photo…",
        usesLidarAssist: true,
        onCancel: {}
    )
    .helmTheme()
}
