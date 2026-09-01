import Core
import DesignSystem
import HealthKitIngest
import SwiftUI

struct UsualMealConfirmRow: View {
    let proposal: UsualMealProposal
    var isLogging = false
    var showsSomethingElse = false
    let onYes: () -> Void
    var onSomethingElse: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            Text(proposal.prompt)
                .helmType(.body)
            Text("\(proposal.energyKcal) kcal")
                .helmType(.monoTag, color: HelmColor.fgMuted)

            if showsSomethingElse {
                VStack(spacing: HelmSpacing.sm) {
                    Button("Yes", action: onYes)
                        .buttonStyle(.helmPrimary)
                        .disabled(isLogging)
                        .accessibilityLabel("Log \(proposal.displayName)")
                    if let onSomethingElse {
                        Button("Something else", action: onSomethingElse)
                            .buttonStyle(.helmSecondary)
                    }
                }
            } else {
                Button(action: onYes) {
                    Text("Yes")
                        .helmType(.label, color: HelmColor.buttonPrimaryForeground)
                        .padding(.horizontal, HelmSpacing.md)
                        .padding(.vertical, HelmSpacing.xs)
                        .background(HelmColor.buttonPrimaryBackground, in: Capsule())
                }
                .buttonStyle(.helmPressable)
                .disabled(isLogging)
                .accessibilityLabel("Log \(proposal.displayName)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
