import DesignSystem
import SwiftUI

struct PhotoMealEstimatingView: View {
    let message: String
    let previewImage: UIImage?

    var body: some View {
        ZStack {
            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .overlay {
                        Color.black.opacity(0.55)
                            .ignoresSafeArea()
                    }
            } else {
                Color.clear
                    .helmScreenBackground()
                    .ignoresSafeArea()
            }

            VStack(spacing: HelmSpacing.lg) {
                ProgressView()
                    .controlSize(.large)
                    .tint(HelmColor.fg)

                VStack(spacing: HelmSpacing.xs) {
                    Text("Analysing meal")
                        .helmType(.title)
                    Text(message)
                        .helmType(.body, color: HelmColor.fgSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, HelmSpacing.lg)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Analysing meal photo")
        }
        .interactiveDismissDisabled()
    }
}

#Preview("Photo estimating") {
    PhotoMealEstimatingView(
        message: "Estimating macros…",
        previewImage: nil
    )
    .helmTheme()
}
