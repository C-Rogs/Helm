import SwiftUI

/// Compact info affordance that opens an ExplainSheet from the parent.
public struct HelmExplainInfoButton: View {
    private let accessibilityLabel: String
    private let action: () -> Void

    public init(
        accessibilityLabel: String = "Show how this is calculated",
        action: @escaping () -> Void
    ) {
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HelmIconView(.info, context: .inline)
                .foregroundStyle(HelmColor.fgMuted)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.helmPressable)
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview("Explain info button") {
    HelmExplainInfoButton(action: {})
        .padding()
        .helmTheme()
}
