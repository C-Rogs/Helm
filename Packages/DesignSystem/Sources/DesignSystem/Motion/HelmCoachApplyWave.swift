import SwiftUI

/// Single accent sweep across the screen when a confirmed coach adjustment applies.
public struct HelmCoachApplyWave: View {
    @Binding private var isActive: Bool

    @Environment(\.helmReduceMotion) private var reduceMotion
    @State private var wavePhase: CGFloat = -1.2
    @State private var clearTask: Task<Void, Never>?

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
        .onChange(of: isActive) { _, active in
            if !active {
                resetWaveState()
            }
        }
        .onDisappear {
            resetWaveState()
        }
    }

    private func playWave() {
        guard isActive else { return }

        clearTask?.cancel()

        if reduceMotion {
            isActive = false
            return
        }

        wavePhase = -1.2
        withAnimation(HelmMotion.animation(HelmMotion.revealAnimation, reduceMotion: reduceMotion)) {
            wavePhase = 1.2
        }

        let duration = HelmMotion.revealDuration(reduceMotion: reduceMotion)
        clearTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            isActive = false
            wavePhase = -1.2
        }
    }

    private func resetWaveState() {
        clearTask?.cancel()
        clearTask = nil
        wavePhase = -1.2
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
