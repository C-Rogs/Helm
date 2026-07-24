import SwiftUI

/// Hairline skeleton placeholder with a tokenized shimmer sweep.
public struct HelmSkeletonBlock: View {
    private let height: CGFloat

    @Environment(\.helmReduceMotion) private var reduceMotion
    @State private var shimmerPhase: CGFloat = -1

    public init(height: CGFloat = 12) {
        self.height = height
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: HelmRadius.sm)
            .fill(HelmColor.gaugeTrack)
            .frame(height: height)
            .overlay {
                if HelmMotion.usesShimmer(reduceMotion: reduceMotion) {
                    GeometryReader { geometry in
                        LinearGradient(
                            colors: [
                                HelmColor.gaugeTrack,
                                HelmColor.surfaceElevated.opacity(0.65),
                                HelmColor.gaugeTrack
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width * 0.45)
                        .offset(x: shimmerPhase * (geometry.size.width * 1.5))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: HelmRadius.sm))
                }
            }
            .opacity(reduceMotion ? 0.75 : 1)
            .onAppear(perform: startShimmerIfNeeded)
    }

    private func startShimmerIfNeeded() {
        guard HelmMotion.usesShimmer(reduceMotion: reduceMotion) else { return }
        shimmerPhase = -1
        withAnimation(HelmMotion.standardAnimation.repeatForever(autoreverses: false)) {
            shimmerPhase = 1
        }
    }
}

/// Card-shaped loading skeleton for screen-level placeholders.
public struct HelmSkeletonCard: View {
    private let rowCount: Int

    public init(rowCount: Int = 3) {
        self.rowCount = rowCount
    }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                HelmSkeletonBlock(height: 14)
                    .frame(width: 120)

                ForEach(0 ..< rowCount, id: \.self) { index in
                    HelmSkeletonBlock()
                        .helmStaggeredAppear(index: index)
                }
            }
        }
    }
}

#if DEBUG
#Preview("Skeleton shimmer") {
    VStack(spacing: HelmSpacing.md) {
        HelmSkeletonCard(rowCount: 4)
    }
    .padding()
    .helmTheme()
}

#Preview("Skeleton reduce motion") {
    HelmSkeletonCard(rowCount: 3)
        .padding()
        .helmTheme()
        .environment(\.helmReduceMotion, true)
}
#endif
