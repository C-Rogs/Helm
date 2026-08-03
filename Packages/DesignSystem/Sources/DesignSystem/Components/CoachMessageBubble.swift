import SwiftUI

public struct CoachMessageBubble: View {
    public enum Role {
        case user
        case assistant
    }

    @Environment(\.helmSkin) private var skin
    @Environment(\.helmPalette) private var palette

    private let role: Role
    private let text: String
    private let isStreaming: Bool
    private let coachName: String

    public init(
        role: Role,
        text: String,
        isStreaming: Bool = false,
        coachName: String = "COACH"
    ) {
        self.role = role
        self.text = text
        self.isStreaming = isStreaming
        self.coachName = coachName
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
                .foregroundStyle(palette.fg)
                .textSelection(.enabled)
                .padding(.horizontal, HelmSpacing.md)
                .padding(.vertical, HelmSpacing.sm)
                .modifier(BubbleChromeModifier(kind: .user, skin: skin, palette: palette))
        }
    }

    private var assistantBubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                HelmSectionEyebrow(coachName.uppercased(), showsArcMark: false)
                Text(displayText)
                    .helmType(.body)
                    .foregroundStyle(palette.fg)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, HelmSpacing.md)
            .padding(.vertical, HelmSpacing.sm)
            .modifier(BubbleChromeModifier(kind: .assistant, skin: skin, palette: palette))
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

private enum BubbleChromeKind {
    case user
    case assistant
}

private struct BubbleChromeModifier: ViewModifier {
    let kind: BubbleChromeKind
    let skin: HelmSkin
    let palette: HelmPalette

    func body(content: Content) -> some View {
        switch skin {
        case .signal:
            content
                .background {
                    Rectangle()
                        .fill(SignalChrome.panelFill(palette: palette))
                }
                .overlay {
                    SignalHUDFrame(emphasized: kind == .assistant)
                }
                .shadow(
                    color: SignalChrome.glow(palette: palette, intensity: kind == .user ? 0.12 : 0.22),
                    radius: 5,
                    y: 0
                )
        case .dataSheet:
            content
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(palette.hairline)
                        .frame(height: 1)
                }
        case .instrument, .stateField, .blueprint:
            content
                .background(
                    kind == .user ? palette.surfaceElevated : palette.surface,
                    in: RoundedRectangle(cornerRadius: HelmRadius.md)
                )
        }
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
    .environment(\.helmSkin, .signal)
}
#endif
