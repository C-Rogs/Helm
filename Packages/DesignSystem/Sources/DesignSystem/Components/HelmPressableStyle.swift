import SwiftUI

/// Press feedback for tappable surfaces that are not primary/secondary buttons.
public struct HelmPressableButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(HelmMotion.quickAnimation, value: configuration.isPressed)
    }
}

/// Press feedback for card-shaped navigation targets.
public struct HelmPressableCardButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.helmSurfacePressed, configuration.isPressed)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(HelmMotion.quickAnimation, value: configuration.isPressed)
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
