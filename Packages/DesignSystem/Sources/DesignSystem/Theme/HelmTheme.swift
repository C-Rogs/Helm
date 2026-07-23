import SwiftUI

public enum HelmThemeMode: String, Sendable, CaseIterable, Identifiable {
    case auto
    case dark
    case light

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .auto: "System"
        case .dark: "Dark"
        case .light: "Light"
        }
    }

    public func resolvedPalette(colorScheme: ColorScheme) -> HelmPalette {
        switch self {
        case .auto:
            colorScheme == .dark ? .dark : .light
        case .dark:
            .dark
        case .light:
            .light
        }
    }

    public func preferredColorScheme(colorScheme: ColorScheme) -> ColorScheme? {
        switch self {
        case .auto: nil
        case .dark: .dark
        case .light: .light
        }
    }
}

@MainActor
@Observable
public final class HelmThemeCoordinator {
    public static let shared = HelmThemeCoordinator()

    public var themeMode: HelmThemeMode {
        didSet { persist() }
    }

    public var skin: HelmSkin {
        didSet { persist() }
    }

    public var hapticsEnabled: Bool {
        didSet { persist() }
    }

    public var thresholdInsightHapticsEnabled: Bool {
        didSet { persist() }
    }

    public private(set) var activePalette: HelmPalette = .dark

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedMode = defaults.string(forKey: Keys.themeMode).flatMap(HelmThemeMode.init(rawValue:))
        themeMode = storedMode ?? .auto
        let storedSkin = defaults.string(forKey: Keys.skin).flatMap(HelmSkin.init(rawValue:))
        if let storedSkin, storedSkin.isSelectable {
            skin = storedSkin
        } else {
            skin = .instrument
        }
        if defaults.object(forKey: Keys.hapticsEnabled) == nil {
            hapticsEnabled = true
        } else {
            hapticsEnabled = defaults.bool(forKey: Keys.hapticsEnabled)
        }
        if defaults.object(forKey: Keys.thresholdInsightHapticsEnabled) == nil {
            thresholdInsightHapticsEnabled = false
        } else {
            thresholdInsightHapticsEnabled = defaults.bool(forKey: Keys.thresholdInsightHapticsEnabled)
        }
    }

    public func update(colorScheme: ColorScheme) {
        let palette = themeMode.resolvedPalette(colorScheme: colorScheme)
        activePalette = palette
        HelmActivePalette.current = palette
    }

    private func persist() {
        defaults.set(themeMode.rawValue, forKey: Keys.themeMode)
        defaults.set(skin.rawValue, forKey: Keys.skin)
        defaults.set(hapticsEnabled, forKey: Keys.hapticsEnabled)
        defaults.set(thresholdInsightHapticsEnabled, forKey: Keys.thresholdInsightHapticsEnabled)
    }

    private enum Keys {
        static let themeMode = "helm.themeMode"
        static let skin = "helm.skin"
        static let hapticsEnabled = "helm.hapticsEnabled"
        static let thresholdInsightHapticsEnabled = "helm.thresholdInsightHapticsEnabled"
    }
}

public struct HelmTheme: Sendable {
    public init() {}
}

private struct HelmThemeKey: EnvironmentKey {
    static let defaultValue = HelmTheme()
}

private struct HelmPaletteKey: EnvironmentKey {
    static let defaultValue = HelmPalette.dark
}

public extension EnvironmentValues {
    var helmTheme: HelmTheme {
        get { self[HelmThemeKey.self] }
        set { self[HelmThemeKey.self] = newValue }
    }

    var helmPalette: HelmPalette {
        get { self[HelmPaletteKey.self] }
        set { self[HelmPaletteKey.self] = newValue }
    }
}

public extension View {
    /// Applies the global Helm theme: palette, accent tint, background, reduce-motion bridge.
    func helmTheme() -> some View {
        HelmThemeContainer(content: self)
    }

    /// Standard screen chrome behind navigation content.
    func helmScreenBackground() -> some View {
        background(HelmColor.canvas)
            .scrollContentBackground(.hidden)
    }
}

private struct HelmThemeContainer<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let content: Content
    @State private var coordinator = HelmThemeCoordinator.shared

    init(content: Content) {
        self.content = content
    }

    var body: some View {
        let palette = coordinator.themeMode.resolvedPalette(colorScheme: colorScheme)
        let preferredScheme = coordinator.themeMode.preferredColorScheme(colorScheme: colorScheme)

        content
            .environment(\.helmTheme, HelmTheme())
            .environment(\.helmPalette, palette)
            .environment(\.helmSkin, coordinator.skin)
            .environment(\.helmReduceMotion, reduceMotion)
            .preferredColorScheme(preferredScheme)
            .tint(palette.accent)
            .background(palette.canvas)
            .onAppear { coordinator.update(colorScheme: colorScheme) }
            .onChange(of: colorScheme) { _, newValue in
                coordinator.update(colorScheme: newValue)
            }
            .onChange(of: coordinator.themeMode) { _, _ in
                coordinator.update(colorScheme: colorScheme)
            }
            .onChange(of: coordinator.skin) { _, _ in
                coordinator.update(colorScheme: colorScheme)
            }
    }
}

#if DEBUG
#Preview("Helm theme") {
    Text("Instrument")
        .helmType(.title)
        .padding()
        .helmTheme()
}
#endif
