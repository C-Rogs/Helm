import SwiftUI

public struct HelmTabSelectionHaptic: ViewModifier {
    @Binding private var selection: Int
    @State private var hasAppeared = false

    public init(selection: Binding<Int>) {
        _selection = selection
    }

    public func body(content: Content) -> some View {
        content
            .onAppear { hasAppeared = true }
            .onChange(of: selection) { oldValue, newValue in
                guard hasAppeared, oldValue != newValue else { return }
                HapticEngine.shared.play(.selection)
            }
    }
}

public extension View {
    func helmTabSelectionHaptic(selection: Binding<Int>) -> some View {
        modifier(HelmTabSelectionHaptic(selection: selection))
    }
}
