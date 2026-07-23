import SwiftUI

public struct PrescriptionRow: View {
    public let label: String
    public let target: String
    public let adjustmentBadge: String?

    public init(label: String, target: String, adjustmentBadge: String? = nil) {
        self.label = label
        self.target = target
        self.adjustmentBadge = adjustmentBadge
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: HelmSpacing.sm) {
            Text(label)
                .helmType(.label)
                .foregroundStyle(HelmColor.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: HelmSpacing.xs) {
                if let adjustmentBadge {
                    Text(adjustmentBadge)
                        .helmType(.monoTag, color: HelmColor.depleted)
                        .padding(.horizontal, HelmSpacing.xs)
                        .padding(.vertical, HelmSpacing.xxs)
                        .background(HelmColor.depleted.opacity(0.12), in: Capsule())
                }

                Text(target)
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

#Preview("Prescription row") {
    VStack(spacing: HelmSpacing.md) {
        PrescriptionRow(
            label: "Bench Press (Barbell)",
            target: "3×8 · 80kg · RPE 8"
        )
        PrescriptionRow(
            label: "Incline DB Press",
            target: "3×8 · RPE 8",
            adjustmentBadge: "-2 SETS"
        )
    }
    .padding()
    .helmTheme()
}
