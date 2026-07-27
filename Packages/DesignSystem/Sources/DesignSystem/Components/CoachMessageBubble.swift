import SwiftUI

public struct CoachMessageBubble: View {
    public enum Role {
        case user
        case assistant
    }

    private let role: Role
    private let text: String
    private let isStreaming: Bool

    public init(role: Role, text: String, isStreaming: Bool = false) {
        self.role = role
        self.text = text
        self.isStreaming = isStreaming
    }

    public var body: some View {
        switch role {
        case .user:
            userBubble
        case .assistant:
            assistantBubble
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: HelmSpacing.xl)
            Text(text)
                .helmType(.body)
                .foregroundStyle(HelmColor.fg)
                .padding(.horizontal, HelmSpacing.md)
                .padding(.vertical, HelmSpacing.sm)
                .background(HelmColor.surfaceElevated, in: RoundedRectangle(cornerRadius: HelmRadius.md))
        }
    }

    private var assistantBubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                HelmSectionEyebrow("COACH", showsArcMark: false)
                Text(displayText)
                    .helmType(.body)
                    .foregroundStyle(HelmColor.fg)
            }
            .padding(.horizontal, HelmSpacing.md)
            .padding(.vertical, HelmSpacing.sm)
            .background(HelmColor.surface, in: RoundedRectangle(cornerRadius: HelmRadius.md))
            Spacer(minLength: HelmSpacing.xl)
        }
    }

    private var displayText: String {
        if text.isEmpty, isStreaming {
            return "..."
        }
        return text
    }
}

#if DEBUG
#Preview("Coach message bubbles") {
    VStack(spacing: HelmSpacing.md) {
        CoachMessageBubble(role: .user, text: "Should I go heavier on bench?")
        CoachMessageBubble(role: .assistant, text: "Stay at 80 kg. Readiness is moderate today.")
        CoachMessageBubble(role: .assistant, text: "", isStreaming: true)
    }
    .padding()
    .helmTheme()
}
#endif
