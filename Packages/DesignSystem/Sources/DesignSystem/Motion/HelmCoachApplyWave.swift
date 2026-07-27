import SwiftUI

/// Single accent sweep across the screen when a confirmed coach adjustment applies.
public struct HelmCoachApplyWave: View {
    @Binding private var isActive: Bool

    @Environment(\.helmReduceMotion) private var reduceMotion
    @State private var wavePhase: CGFloat = -1.2

    public init(isActive: Binding<Bool>) {
        _isActive = isActive
    }

    public var body: some View {
        GeometryReader { geometry in
            if isActive {
                LinearGradient(
                    colors: [
                        HelmColor.accent.opacity(0),
                        HelmColor.accent.opacity(0.35),
                        HelmColor.accent.opacity(0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geometry.size.width * 0.55)
                .offset(x: wavePhase * geometry.size.width)
                .allowsHitTesting(false)
                .onAppear(perform: playWave)
            }
        }
        .ignoresSafeArea()
    }

    private func playWave() {
        guard isActive else { return }

        if reduceMotion {
            isActive = false
            return
        }

        wavePhase = -1.2
        withAnimation(HelmMotion.revealAnimation) {
            wavePhase = 1.2
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + HelmMotion.revealDuration(reduceMotion: reduceMotion)) {
            isActive = false
        }
    }
}

#if DEBUG
#Preview("Coach apply wave") {
    struct PreviewContainer: View {
        @State private var active = true

        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                Text("Workout")
                    .helmType(.title)
                    .foregroundStyle(.white)
                HelmCoachApplyWave(isActive: $active)
            }
            .helmTheme()
        }
    }

    return PreviewContainer()
}
#endif
