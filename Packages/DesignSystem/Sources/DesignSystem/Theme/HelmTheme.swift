import SwiftUI

public struct HelmTheme: Sendable {
    public init() {}
}

private struct HelmThemeKey: EnvironmentKey {
    static let defaultValue = HelmTheme()
}

public extension EnvironmentValues {
    var helmTheme: HelmTheme {
        get { self[HelmThemeKey.self] }
        set { self[HelmThemeKey.self] = newValue }
    }
}

public extension View {
    /// Applies the global OLED-black theme: dark colour scheme, accent tint, background.
    func helmTheme() -> some View {
        self
            .environment(\.helmTheme, HelmTheme())
            .preferredColorScheme(.dark)
            .tint(HelmColor.accent)
            .background(HelmColor.background)
    }

    /// Standard screen chrome: black background behind navigation content.
    func helmScreenBackground() -> some View {
        self
            .background(HelmColor.background)
            .scrollContentBackground(.hidden)
    }
}
