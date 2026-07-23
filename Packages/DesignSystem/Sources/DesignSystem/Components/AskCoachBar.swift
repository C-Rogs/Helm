import SwiftUI

public struct AskCoachBar: View {
    public let prompt: String
    public let isLoading: Bool
    public let action: () -> Void

    @Environment(\.helmReduceMotion) private var reduceMotion
    @State private var pulse = false

    public init(
        prompt: String = "Ask coach…",
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.prompt = prompt
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: HelmSpacing.sm) {
                statusIndicator

                Text(prompt)
                    .helmType(.body, color: HelmColor.fg)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, HelmSpacing.md)
            .padding(.vertical, HelmSpacing.sm)
            .background(HelmColor.surfaceElevated, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(HelmColor.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onAppear {
            if !isLoading {
                pulse = true
            }
        }
        .onChange(of: isLoading) { _, loading in
            pulse = !loading
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
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
                        reduceMotion ? nil : .easeInOut(duration: 1).repeatForever(autoreverses: true),
                        value: pulse
                    )
            }
        }
        .frame(width: 16, height: 16)
    }
}

#Preview("Ask coach bar") {
    VStack(spacing: HelmSpacing.md) {
        Spacer()
        AskCoachBar(prompt: "Cable fly is taken") {}
        AskCoachBar(prompt: "Adjusting session…", isLoading: true) {}
            .padding()
    }
    .helmTheme()
    .helmScreenBackground()
}
