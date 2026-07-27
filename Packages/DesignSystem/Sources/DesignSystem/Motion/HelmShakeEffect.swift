import SwiftUI

struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 6
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(translationX: amount * sin(animatableData * .pi * shakes), y: 0)
        )
    }
}

extension View {
    public func helmShake(trigger: Int, reduceMotion: Bool) -> some View {
        modifier(HelmShakeModifier(trigger: trigger, reduceMotion: reduceMotion))
    }
}

private struct HelmShakeModifier: ViewModifier {
    let trigger: Int
    let reduceMotion: Bool
    @State private var shakeAmount: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .modifier(ShakeEffect(animatableData: shakeAmount))
            .onChange(of: trigger) { _, _ in
                guard !reduceMotion, trigger > 0 else { return }
                shakeAmount = 0
                withAnimation(.default) {
                    shakeAmount = 1
                }
            }
    }
}
