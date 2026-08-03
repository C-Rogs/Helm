import SwiftUI

/// List / Form row chrome that follows `HelmSkin` so Settings and editors stay consistent.
public struct HelmListRowBackground: View {
    @Environment(\.helmSkin) private var skin
    @Environment(\.helmPalette) private var palette

    public init() {}

    public var body: some View {
        switch skin {
        case .signal:
            Color.clear
        case .instrument, .stateField, .blueprint:
            palette.surface
        case .dataSheet:
            palette.canvas
        }
    }
}

public extension View {
    /// Applies skin-aware list row background + separator treatment.
    func helmListRowChrome() -> some View {
        modifier(HelmListRowChromeModifier())
    }
}

private struct HelmListRowChromeModifier: ViewModifier {
    @Environment(\.helmSkin) private var skin
    @Environment(\.helmPalette) private var palette

    func body(content: Content) -> some View {
        content
            .listRowBackground(HelmListRowBackground())
            .listRowSeparatorTint(skin == .signal ? palette.accent.opacity(0.25) : palette.hairline)
    }
}
