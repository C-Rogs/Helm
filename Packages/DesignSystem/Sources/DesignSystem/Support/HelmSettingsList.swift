import SwiftUI

public extension View {
    /// Shared Settings list chrome: plain list, hidden scroll bg, skin-aware rows, screen canvas.
    func helmSettingsListChrome() -> some View {
        modifier(HelmSettingsListChromeModifier())
    }
}

private struct HelmSettingsListChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .listRowBackground(HelmListRowBackground())
            .helmScreenBackground()
    }
}
