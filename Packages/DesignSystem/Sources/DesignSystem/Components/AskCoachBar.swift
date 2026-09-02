import SwiftUI

public struct AskCoachBar: View {
    public let prompt: String
    public let peekSnippet: String?
    public let isLoading: Bool
    public let action: () -> Void

    public init(
        prompt: String = "Ask coach",
        peekSnippet: String? = nil,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.prompt = prompt
        self.peekSnippet = peekSnippet
        self.isLoading = isLoading
        self.action = action
    }

    private var displayPrompt: String {
        if let peekSnippet, !peekSnippet.isEmpty {
            return peekSnippet
        }
        return prompt
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: HelmSpacing.sm) {
                statusIndicator

                Text(displayPrompt)
                    .helmType(.body, color: HelmColor.fg)
                    .lineLimit(peekSnippet == nil ? 1 : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, HelmSpacing.md)
            .padding(.vertical, HelmSpacing.sm)
            .background(
                (isLoading ? HelmColor.accent.opacity(0.12) : HelmColor.surfaceElevated),
                in: Capsule()
            )
            .overlay {
                if isLoading {
                    HelmBrushedAccentRim(shape: Capsule(), isLive: true)
                } else {
                    Capsule()
                        .stroke(HelmColor.hairline, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.helmPressable)
        .disabled(isLoading)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        CoachAIPulseIndicator(isLoading: isLoading)
    }
}

#Preview("Ask coach bar") {
    VStack(spacing: HelmSpacing.md) {
        Spacer()
        AskCoachBar(prompt: "Cable fly is taken") {}
        AskCoachBar(prompt: "Adjusting session", isLoading: true) {}
            .padding()
    }
    .helmTheme()
    .helmScreenBackground()
}
