import DesignSystem
import HealthKitIngest
import SwiftUI

struct DailyEnergyBreakdownSection: View {
    let breakdown: DailyEnergyBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text("Energy breakdown")
                .helmType(.label)

            summaryRows

            if !breakdown.workoutContributors.isEmpty {
                contributorSection
            }

            otherActivityRow

            Text("Workout burn is nested inside Apple Health active energy, not added on top.")
                .helmType(.monoTag, color: HelmColor.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var summaryRows: some View {
        VStack(spacing: HelmSpacing.xs) {
            if let intake = breakdown.intakeKcal {
                energyRow(
                    label: "In",
                    value: "\(intake) kcal",
                    detail: "Logged food",
                    provenance: nil
                )
            }

            if let resting = breakdown.restingKcal {
                energyRow(
                    label: "Resting",
                    value: "\(resting) kcal",
                    detail: EnergyProvenance.appleHealth.displayLabel,
                    provenance: EnergyProvenance.appleHealth.displayLabel
                )
            }

            activeRow

            if let totalOut = breakdown.totalOutKcal {
                energyRow(
                    label: "Total out",
                    value: "\(totalOut) kcal",
                    detail: "Resting + active",
                    provenance: EnergyProvenance.appleHealth.displayLabel
                )
            }

            if let net = breakdown.netKcal {
                energyRow(
                    label: "Net",
                    value: signedKcal(net),
                    detail: net >= 0 ? "Surplus" : "Deficit",
                    provenance: nil,
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
                    value: "\(partial) kcal",
                    detail: ActiveEnergyDisplayCopy.stalePartial,
                    provenance: EnergyProvenance.appleHealth.displayLabel
                )
            } else {
                energyRow(
                    label: "Active",
                    value: "Syncing",
                    detail: ActiveEnergyDisplayCopy.stalePending,
                    provenance: EnergyProvenance.appleHealth.displayLabel
                )
            }
        case let .fresh(active):
            energyRow(
                label: "Active",
                value: "\(active) kcal",
                detail: ActiveEnergyDisplayCopy.freshDetail,
                provenance: EnergyProvenance.appleHealth.displayLabel
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
                    value: "\(contributor.kilocalories) kcal",
                    detail: contributor.detail ?? contributor.provenance.displayLabel,
                    provenance: contributor.provenance.displayLabel
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
                value: "Syncing",
                detail: "Apple Health is still reconciling today's active energy",
                provenance: EnergyProvenance.appleHealth.displayLabel
            )
        case let .unreconciled(workoutTotal, activeTotal):
            energyRow(
                label: "Other activity",
                value: "Unreconciled",
                detail: "Workouts report \(workoutTotal) kcal inside \(activeTotal) kcal active. Refresh after Apple Health catches up.",
                provenance: EnergyProvenance.appleHealth.displayLabel
            )
        case let .reconciled(kilocalories):
            if kilocalories > 0 {
                energyRow(
                    label: "Other activity",
                    value: "\(kilocalories) kcal",
                    detail: "Steps and movement outside logged workouts",
                    provenance: EnergyProvenance.appleHealth.displayLabel
                )
            }
        }
    }

    private func energyRow(
        label: String,
        value: String,
        detail: String,
        provenance: String?,
        valueColor: Color = HelmColor.fg
    ) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .helmType(.body, color: HelmColor.fgSecondary)
                Spacer()
                Text(value)
                    .helmType(.body, color: valueColor)
            }
            HStack(spacing: HelmSpacing.xxs) {
                Text(detail)
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                if let provenance {
                    Text("·")
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                    Text(provenance)
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                }
            }
        }
        .padding(.vertical, HelmSpacing.xxs)
    }

    private func signedKcal(_ value: Int) -> String {
        if value > 0 { return "+\(value) kcal" }
        return "\(value) kcal"
    }
}
