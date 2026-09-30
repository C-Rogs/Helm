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
            return "Signal used LiDAR depth to refine portion size, then estimates ingredients, portion detail, and macros directly from the photo."
        }
        return "Signal estimates ingredients, portion detail, and macros directly from the photo."
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
                        footnote: footnote,
                        isImpactful: true
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
        completedSteps: ["Reading photo", "Analysing portions and ingredients…"],
        currentStep: "Building draft…",
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
        currentStep: "Analysing portions and ingredients…",
        usesLidarAssist: true,
        onCancel: {}
    )
    .helmTheme()
}
