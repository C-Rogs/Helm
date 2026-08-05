import SwiftUI

public extension View {
    /// Shared matched-geometry id for card-to-detail navigation transitions.
    func helmMatchedCardDetail<ID: Hashable>(
        id: ID,
        in namespace: Namespace.ID,
        isSource: Bool = true,
        properties: MatchedGeometryProperties = .frame,
        anchor: UnitPoint = .center
    ) -> some View {
        matchedGeometryEffect(
            id: id,
            in: namespace,
            properties: properties,
            anchor: anchor,
            isSource: isSource
        )
    }
}

#if DEBUG
#Preview("Matched card detail") {
    struct PreviewHarness: View {
        @Namespace private var namespace
        @State private var isShowingDetail = false

        var body: some View {
            NavigationStack {
                VStack(spacing: HelmSpacing.md) {
                    if !isShowingDetail {
                        Card {
                            Text("72")
                                .helmType(.heroNumber)
                        }
                        .helmMatchedCardDetail(id: "score", in: namespace)
                        .onTapGesture {
                            withAnimation(
                                HelmMotion.animation(HelmMotion.standardAnimation, reduceMotion: false)
                            ) {
                                isShowingDetail = true
                            }
                        }
                    } else {
                        Card {
                            VStack(spacing: HelmSpacing.sm) {
                                HelmNumericText(72)
                                    .helmType(.heroNumber)
                                Text("Readiness detail")
                                    .helmType(.body, color: HelmColor.fgMuted)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .helmMatchedCardDetail(id: "score", in: namespace, isSource: false)
                    }
                }
                .padding()
                .helmTheme()
            }
        }
    }

    return PreviewHarness()
}
#endif
