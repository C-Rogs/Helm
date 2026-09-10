import DesignSystem
import HealthKitIngest
import SwiftUI

struct DailyEnergyBreakdownSection: View {
    let breakdown: DailyEnergyBreakdown
    @State private var isShowingDescriptor = false

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            HStack(spacing: HelmSpacing.xs) {
                Text("Energy breakdown")
                    .helmType(.label)
                HelmExplainInfoButton(
                    accessibilityLabel: "Explain energy breakdown"
                ) {
                    isShowingDescriptor = true
                }
            }

            summaryRows

            if !breakdown.workoutContributors.isEmpty {
                contributorSection
            }

            otherActivityRow
        }
        .popover(isPresented: $isShowingDescriptor, arrowEdge: .top) {
            Text("Active is the total active energy reported by Apple Health. Workout burn is included in Active. Other activity is the remaining active energy after workout contributors are reconciled.")
                .helmType(.body, color: HelmColor.fgSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(HelmSpacing.md)
                .presentationCompactAdaptation(.popover)
        }
    }

    private var summaryRows: some View {
        VStack(spacing: HelmSpacing.xs) {
            if let intake = breakdown.intakeKcal {
                energyRow(
                    label: "In",
                    value: "\(intake) kcal"
                )
            }

            if let resting = breakdown.restingKcal {
                energyRow(
                    label: "Resting",
                    value: "\(resting) kcal"
                )
            }

            activeRow

            if let totalOut = breakdown.totalOutKcal {
                energyRow(
                    label: "Total out",
                    value: "\(totalOut) kcal"
                )
            }

            if let net = breakdown.netKcal {
                energyRow(
                    label: "Net",
                    value: signedKcal(net),
                    valueColor: net >= 0 ? HelmColor.ready : HelmColor.depleted
                )
            }
        }
    }

    @ViewBuilder
    private var activeRow: some View {
        switch breakdown.activeFreshness {
        case .unavailable:
            EmptyView()
        case let .stale(partial):
            if let partial, partial > 0 {
                energyRow(
                    label: "Active",
                    value: "\(partial) kcal"
                )
            } else {
                energyRow(
                    label: "Active",
                    value: "Syncing"
                )
            }
        case let .fresh(active):
            energyRow(
                label: "Active",
                value: "\(active) kcal"
            )
        }
    }

    private var contributorSection: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            Text("Workout contributors")
                .helmType(.monoTag, color: HelmColor.fgSecondary)

            ForEach(breakdown.workoutContributors) { contributor in
                energyRow(
                    label: contributor.title,
                    value: "\(contributor.kilocalories) kcal"
                )
            }
        }
    }

    @ViewBuilder
    private var otherActivityRow: some View {
        switch breakdown.otherActivity {
        case .unavailable:
            EmptyView()
        case .syncing:
            energyRow(
                label: "Other activity",
                value: "Syncing"
            )
        case .unreconciled:
            energyRow(
                label: "Other activity",
                value: "Unreconciled"
            )
        case let .reconciled(kilocalories):
            if kilocalories > 0 {
                energyRow(
                    label: "Other activity",
                    value: "\(kilocalories) kcal"
                )
            }
        }
    }

    private func energyRow(
        label: String,
        value: String,
        valueColor: Color = HelmColor.fg
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .helmType(.body, color: HelmColor.fgSecondary)
            Spacer()
            Text(value)
                .helmType(.body, color: valueColor)
        }
        .padding(.vertical, HelmSpacing.xxs)
    }

    private func signedKcal(_ value: Int) -> String {
        if value > 0 { return "+\(value) kcal" }
        return "\(value) kcal"
    }
}
