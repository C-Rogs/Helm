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
        let scale = reduceMotion ? 1.0 : skin.pressScale
        switch kind {
        case .plain:
            configuration.label
                .opacity(configuration.isPressed ? 0.72 : 1)
                .scaleEffect(configuration.isPressed ? scale : 1)
                .animation(
                    reduceMotion ? nil : HelmMotion.quickAnimation,
                    value: configuration.isPressed
                )
        case .card:
            configuration.label
                .environment(\.helmSurfacePressed, configuration.isPressed)
                .opacity(configuration.isPressed ? (skin == .signal ? 0.88 : 0.92) : 1)
                .scaleEffect(configuration.isPressed ? scale : 1)
                .animation(
                    reduceMotion ? nil : HelmMotion.quickAnimation,
                    value: configuration.isPressed
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
