import DesignSystem
import SwiftUI

struct PhotoMealEstimatingView: View {
    let previewImage: UIImage?
    let completedSteps: [String]
    let currentStep: String
    let onCancel: () -> Void

    @State private var shimmerPhase: CGFloat = 0

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundLayer

                VStack(spacing: HelmSpacing.lg) {
                    Spacer()

                    statusCard

                    Spacer()
                }
                .padding(HelmSpacing.md)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: true)) {
                shimmerPhase = 1
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Analysing meal photo")
    }

    private var backgroundLayer: some View {
        ZStack {
            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            } else {
                Color.clear
                    .helmScreenBackground()
                    .ignoresSafeArea()
            }

            LinearGradient(
                colors: [
                    HelmColor.canvas.opacity(0.55),
                    HelmColor.buttonPrimaryBackground.opacity(0.35 + shimmerPhase * 0.15),
                    HelmColor.canvas.opacity(0.75),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: shimmerPhase)

            RadialGradient(
                colors: [
                    HelmColor.buttonPrimaryBackground.opacity(0.25),
                    Color.clear,
                ],
                center: .center,
                startRadius: 40,
                endRadius: 280
            )
            .scaleEffect(1 + shimmerPhase * 0.08)
            .ignoresSafeArea()
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.md) {
            HStack(spacing: HelmSpacing.sm) {
                ProgressView()
                    .tint(HelmColor.fg)
                Text("Analysing meal")
                    .helmType(.title, color: HelmColor.fg)
            }

            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                ForEach(completedSteps, id: \.self) { step in
                    HStack(spacing: HelmSpacing.xs) {
                        HelmIconView(.checkmark, context: .inline)
                            .foregroundStyle(HelmColor.positive)
                        Text(step)
                            .helmType(.body, color: HelmColor.fg)
                    }
                }

                HStack(spacing: HelmSpacing.xs) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(HelmColor.fg)
                    Text(currentStep)
                        .helmType(.body, color: HelmColor.fg)
                }
            }

            Text("Helm identifies ingredients with vision, then matches each item to CoFID on your phone.")
                .helmType(.body, color: HelmColor.fgSecondary)
        }
        .padding(HelmSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: HelmRadius.md)
                .fill(HelmColor.surface.opacity(0.94))
        )
        .overlay {
            RoundedRectangle(cornerRadius: HelmRadius.md)
                .strokeBorder(HelmColor.hairline.opacity(0.6), lineWidth: 1)
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
