import SwiftUI

public struct HelmStaggeredAppearModifier: ViewModifier {
    public let index: Int
    public let staggerStep: TimeInterval

    @Environment(\.helmReduceMotion) private var reduceMotion
    @State private var appeared = false

    public init(index: Int, staggerStep: TimeInterval = 0.04) {
        self.index = index
        self.staggerStep = staggerStep
    }

    public func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 8)
            .onAppear {
                let delay = HelmMotion.staggerDelay(
                    index: index,
                    step: staggerStep,
                    reduceMotion: reduceMotion
                )
                if delay == 0 {
                    withAnimation(HelmMotion.animation(HelmMotion.quickAnimation, reduceMotion: reduceMotion)) {
                        appeared = true
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        withAnimation(HelmMotion.animation(HelmMotion.quickAnimation, reduceMotion: reduceMotion)) {
                            appeared = true
                        }
                    }
                }
            }
    }
}

public extension View {
    func helmStaggeredAppear(index: Int, staggerStep: TimeInterval = 0.04) -> some View {
        modifier(HelmStaggeredAppearModifier(index: index, staggerStep: staggerStep))
    }
}

#if DEBUG
#Preview("Staggered appear") {
    ScrollView {
        VStack(spacing: HelmSpacing.sm) {
            ForEach(0 ..< 6, id: \.self) { index in
                Card {
                    Text("Row \(index + 1)")
                        .helmType(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .helmStaggeredAppear(index: index)
            }
        }
        .padding()
    }
    .helmTheme()
}

#Preview("Staggered appear reduce motion") {
    Card {
        Text("Instant cross-fade")
            .helmType(.body)
    }
    .helmStaggeredAppear(index: 3)
    .padding()
    .helmTheme()
    .environment(\.helmReduceMotion, true)
}
#endif
