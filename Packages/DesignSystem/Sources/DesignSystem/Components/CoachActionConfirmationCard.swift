import SwiftUI

/// Confirm-before-apply card for coach mutations (adjust, workout start, food log).
public struct CoachActionConfirmationCard: View {
    private let title: String
    private let detail: String
    private let reason: String?
    private let errorMessage: String?
    private let confirmLabel: String
    private let cancelLabel: String
    private let retryLabel: String
    private let isRetryDisabled: Bool
    private let onConfirm: () -> Void
    private let onCancel: () -> Void
    private let onRetry: (() -> Void)?

    public init(
        title: String,
        detail: String,
        reason: String? = nil,
        errorMessage: String? = nil,
        confirmLabel: String = "Apply",
        cancelLabel: String = "Keep plan",
        retryLabel: String = "Try again",
        isRetryDisabled: Bool = false,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onRetry: (() -> Void)? = nil
    ) {
        self.title = title
        self.detail = detail
        self.reason = reason
        self.errorMessage = errorMessage
        self.confirmLabel = confirmLabel
        self.cancelLabel = cancelLabel
        self.retryLabel = retryLabel
        self.isRetryDisabled = isRetryDisabled
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.onRetry = onRetry
    }

    private var resolvedError: String? {
        guard let errorMessage, !errorMessage.isEmpty else { return nil }
        return errorMessage
    }

    private var hasError: Bool { resolvedError != nil }

    public var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.md) {
            HelmSectionEyebrow(hasError ? "COULD NOT APPLY" : "CONFIRM CHANGE")

            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                Text(title)
                    .helmType(.label, color: HelmColor.fg)
                Text(detail)
                    .helmType(.body, color: HelmColor.fgSecondary)
            }

            if let reason, !reason.isEmpty, !hasError {
                Text(reason)
                    .helmType(.body, color: HelmColor.fgSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let resolvedError {
                Text(resolvedError)
                    .helmType(.body, color: HelmColor.depleted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: HelmSpacing.sm) {
                if hasError {
                    Button(retryLabel) {
                        (onRetry ?? onConfirm)()
                    }
                    .buttonStyle(.helmPrimary)
                    .disabled(isRetryDisabled)

                    Button(cancelLabel, action: onCancel)
                        .buttonStyle(.helmSecondary)
                } else {
                    Button(confirmLabel, action: onConfirm)
                        .buttonStyle(.helmPrimary)

                    Button(cancelLabel, action: onCancel)
                        .buttonStyle(.helmSecondary)
                }
            }
        }
        .padding(HelmSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hasError ? HelmColor.depleted.opacity(0.08) : Color.clear)
        .helmPanelChrome(hasError ? .elevated : .accentQuiet)
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

#Preview("Coach action failure") {
    CoachActionConfirmationCard(
        title: "Start workout",
        detail: "Push · Bench Press, OHP",
        errorMessage: "Could not start. Active session already open.",
        confirmLabel: "Start workout",
        cancelLabel: "Not yet",
        onConfirm: {},
        onCancel: {},
        onRetry: {}
    )
    .helmScreenPadding()
    .padding()
    .helmTheme()
}
#endif
