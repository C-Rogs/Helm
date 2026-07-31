import SwiftUI

/// Confirm-before-apply card for coach mutations (adjust, workout start, food log).
public struct CoachActionConfirmationCard: View {
    private let title: String
    private let detail: String
    private let reason: String?
    private let confirmLabel: String
    private let cancelLabel: String
    private let onConfirm: () -> Void
    private let onCancel: () -> Void

    public init(
        title: String,
        detail: String,
        reason: String? = nil,
        confirmLabel: String = "Apply",
        cancelLabel: String = "Keep plan",
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.detail = detail
        self.reason = reason
        self.confirmLabel = confirmLabel
        self.cancelLabel = cancelLabel
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.md) {
            HelmSectionEyebrow("CONFIRM CHANGE")

            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                Text(title)
                    .helmType(.label, color: HelmColor.fg)
                Text(detail)
                    .helmType(.body, color: HelmColor.fgSecondary)
            }

            if let reason, !reason.isEmpty {
                Text(reason)
                    .helmType(.body, color: HelmColor.fgSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: HelmSpacing.sm) {
                Button(confirmLabel, action: onConfirm)
                    .buttonStyle(.helmPrimary)

                Button(cancelLabel, action: onCancel)
                    .buttonStyle(.helmSecondary)
            }
        }
        .padding(HelmSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HelmColor.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: HelmRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: HelmRadius.md)
                .strokeBorder(HelmColor.accent.opacity(0.35), lineWidth: 1)
        }
    }
}

#if DEBUG
#Preview("Coach action confirmation") {
    CoachActionConfirmationCard(
        title: "Log lunch",
        detail: "Chicken rice bowl · 450 kcal",
        reason: "Matches what you described.",
        confirmLabel: "Log meal",
        cancelLabel: "Cancel",
        onConfirm: {},
        onCancel: {}
    )
    .helmScreenPadding()
    .padding()
    .helmTheme()
}
#endif
