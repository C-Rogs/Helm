import SwiftUI

/// Press feedback for tappable surfaces that are not primary/secondary buttons.
public struct HelmPressableButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration, kind: .plain)
    }
}

/// Press feedback for card-shaped navigation targets.
public struct HelmPressableCardButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration, kind: .card)
    }
}

private enum PressableKind {
    case plain
    case card
}

private struct PressableLabel: View {
    @Environment(\.helmSkin) private var skin
    @Environment(\.helmReduceMotion) private var reduceMotion

    let configuration: ButtonStyleConfiguration
    let kind: PressableKind

    var body: some View {
        switch kind {
        case .plain:
            configuration.label
                .helmPressChrome(
                    isPressed: configuration.isPressed,
                    scale: skin.pressScale,
                    pressedOpacity: 0.72,
                    reduceMotion: reduceMotion
                )
        case .card:
            configuration.label
                .environment(\.helmSurfacePressed, configuration.isPressed)
                .helmPressChrome(
                    isPressed: configuration.isPressed,
                    scale: skin.pressScale,
                    pressedOpacity: skin == .signal ? 0.88 : 0.92,
                    reduceMotion: reduceMotion
                )
        }
    }
}

private struct HelmSurfacePressedKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    var helmSurfacePressed: Bool {
        get { self[HelmSurfacePressedKey.self] }
        set { self[HelmSurfacePressedKey.self] = newValue }
    }
}

public extension View {
    /// Instant-down, spring-up press chrome. Pair with `ButtonStyleConfiguration.isPressed`.
    func helmPressChrome(
        isPressed: Bool,
        scale: CGFloat,
        pressedOpacity: Double,
        reduceMotion: Bool
    ) -> some View {
        opacity(isPressed ? pressedOpacity : 1)
            .scaleEffect((isPressed && !reduceMotion) ? scale : 1)
            .animation(
                HelmMotion.pressAnimation(isPressed: isPressed, reduceMotion: reduceMotion),
                value: isPressed
            )
    }
}

#Preview("Pressable styles") {
    VStack(spacing: HelmSpacing.md) {
        Button("Plain pressable") {}
            .buttonStyle(.helmPressable)
            .padding()
            .background(HelmColor.surfaceElevated, in: RoundedRectangle(cornerRadius: HelmRadius.sm))

        Button {
        } label: {
            Card {
                Text("Card navigation")
                    .helmType(.label)
            }
        }
        .buttonStyle(.helmPressableCard)
    }
    .padding()
    .helmTheme()
}
