import SwiftUI

public struct StatRow: View {
    private let label: String
    private let value: String
    private let detail: String?

    public init(label: String, value: String, detail: String? = nil) {
        self.label = label
        self.value = value
        self.detail = detail
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .helmType(.body, color: HelmColor.textSecondary)

            Spacer(minLength: HelmSpacing.sm)

            VStack(alignment: .trailing, spacing: HelmSpacing.xxs) {
                Text(value)
                    .helmType(.bigNumber, color: HelmColor.textPrimary)
                    .helmNumericRoll(value: value)
                if let detail {
                    Text(detail)
                        .helmType(.body, color: HelmColor.textTertiary)
                }
            }
        }
    }
}

#Preview("StatRow") {
    VStack(spacing: HelmSpacing.md) {
        StatRow(label: "HRV", value: "48 ms", detail: "z +0.4")
        StatRow(label: "Sleep", value: "7h 12m")
    }
    .padding()
    .helmTheme()
}
