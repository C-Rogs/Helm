import DesignSystem
import SwiftUI

/// Async image loader for exercise demonstration photos (gif_url from the seed catalog).
struct ExerciseImageView: View {
    let url: URL?
    let fallbackLabel: String

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        fallback
                    case .empty:
                        loadingPlaceholder
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HelmColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: HelmRadius.md))
    }

    private var fallback: some View {
        ZStack {
            HelmColor.surfaceElevated
            VStack(spacing: HelmSpacing.xs) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.largeTitle)
                    .foregroundStyle(HelmColor.fgMuted)
                Text(fallbackLabel)
                    .helmType(.monoTag, color: HelmColor.fgMuted)
            }
        }
    }

    private var loadingPlaceholder: some View {
        ZStack {
            HelmColor.surfaceElevated
            ProgressView()
                .tint(HelmColor.fgMuted)
        }
    }
}

#Preview("Exercise image with URL") {
    ExerciseImageView(
        url: URL(string: "https://example.com/exercise.gif"),
        fallbackLabel: "Bench Press"
    )
    .frame(height: 200)
    .padding()
    .helmTheme()
}

#Preview("Exercise image fallback") {
    ExerciseImageView(
        url: nil,
        fallbackLabel: "Squat"
    )
    .frame(height: 200)
    .padding()
    .helmTheme()
}
