import SwiftUI

/// Labeled status value for settings and connection screens.
public struct HelmStatusRow: View {
    private let label: String
    private let value: String
    private let valueColor: Color

    public init(label: String, value: String, valueColor: Color = HelmColor.fg) {
        self.label = label
        self.value = value
        self.valueColor = valueColor
    }

    public var body: some View {
        LabeledContent(label) {
            Text(value)
                .helmType(.label, color: valueColor)
        }
    }
}

#Preview("HelmStatusRow") {
    List {
        HelmStatusRow(label: "Account", value: "Linked", valueColor: HelmColor.ready)
        HelmStatusRow(label: "App Remote", value: "Idle", valueColor: HelmColor.fgMuted)
    }
    .helmTheme()
}
