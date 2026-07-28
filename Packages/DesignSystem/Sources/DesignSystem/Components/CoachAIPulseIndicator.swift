import SwiftUI

/// Pulsing accent dot used while coach or vision models are working.
public struct CoachAIPulseIndicator: View {
    public let isLoading: Bool

    @Environment(\.helmReduceMotion) private var reduceMotion
    @State private var pulse = false

    public init(isLoading: Bool = true) {
        self.isLoading = isLoading
    }

    public var body: some View {
        ZStack {
            if isLoading {
                ProgressView()
                    .tint(HelmColor.accent)
            } else {
                Circle()
                    .fill(HelmColor.accent)
                    .overlay {
                        Circle()
                            .fill(HelmColor.accent)
                            .scaleEffect(pulse && !reduceMotion ? 1.25 : 1)
                            .opacity(pulse && !reduceMotion ? 0.65 : 1)
                    }
                    .animation(
                        reduceMotion ? nil : HelmMotion.pulseAnimation.repeatForever(autoreverses: true),
                        value: pulse
                    )
            }
        }
        .frame(width: 16, height: 16)
        .onAppear {
            if !isLoading {
                pulse = true
            }
        }
        .onChange(of: isLoading) { _, loading in
            pulse = !loading
        }
    }
}

#if DEBUG
#Preview("Coach AI pulse") {
    HStack(spacing: HelmSpacing.md) {
        CoachAIPulseIndicator(isLoading: true)
        CoachAIPulseIndicator(isLoading: false)
    }
    .padding()
    .helmTheme()
}
#endif
