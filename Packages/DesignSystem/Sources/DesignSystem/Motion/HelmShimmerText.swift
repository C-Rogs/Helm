import SwiftUI

/// Waiting/status text with a left-to-right highlight sweep (Cursor-style thinking shine).
public struct HelmShimmerText: View {
    private let text: String
    private let style: HelmType
    private let baseColor: Color
    private let highlightColor: Color
    private let lineLimit: Int?

    @Environment(\.helmReduceMotion) private var reduceMotion
    @State private var shimmerPhase: CGFloat = -1

    private static let sweepDuration: TimeInterval = 1.6

    public init(
        _ text: String,
        style: HelmType = .body,
        baseColor: Color = HelmColor.fgSecondary,
        highlightColor: Color = HelmColor.fg,
        lineLimit: Int? = nil
    ) {
        self.text = text
        self.style = style
        self.baseColor = baseColor
        self.highlightColor = highlightColor
        self.lineLimit = lineLimit
    }

    public var body: some View {
        Group {
            if HelmMotion.usesShimmer(reduceMotion: reduceMotion) {
                animatedText
            } else {
                labeledText(color: baseColor)
            }
        }
        .accessibilityLabel(text)
    }

    private var animatedText: some View {
        labeledText(color: baseColor)
            .overlay {
                labeledText(color: highlightColor)
                    .mask {
                        GeometryReader { geometry in
                            let bandWidth = max(geometry.size.width * 0.45, 24)
                            LinearGradient(
                                colors: [
                                    .clear,
                                    .white.opacity(0.15),
                                    .white,
                                    .white.opacity(0.15),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: bandWidth)
                            .offset(x: shimmerPhase * (geometry.size.width + bandWidth) - bandWidth)
                        }
                    }
            }
            .onAppear(perform: startShimmerIfNeeded)
    }

    private func labeledText(color: Color) -> some View {
        Text(text)
            .helmType(style, color: color)
            .lineLimit(lineLimit)
    }

    private func startShimmerIfNeeded() {
        guard HelmMotion.usesShimmer(reduceMotion: reduceMotion) else { return }
        shimmerPhase = -1
        withAnimation(
            .easeInOut(duration: Self.sweepDuration).repeatForever(autoreverses: false)
        ) {
            shimmerPhase = 1
        }
    }
}

#if DEBUG
#Preview("Shimmer text") {
    VStack(alignment: .leading, spacing: HelmSpacing.md) {
        HelmShimmerText("Coach thinking")
        HelmShimmerText("...", style: .body)
        HelmShimmerText("Matching ingredients to CoFID…")
    }
    .padding()
    .helmTheme()
    .helmScreenBackground()
}

#Preview("Shimmer reduce motion") {
    HelmShimmerText("Coach thinking")
        .padding()
        .helmTheme()
        .environment(\.helmReduceMotion, true)
}
#endif
