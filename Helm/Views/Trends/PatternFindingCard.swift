import DesignSystem
import HealthKitIngest
import SwiftUI

struct PatternFindingCard: View {
    let model: PatternFindingCardModel
    var onConfirmToMemory: (() -> Void)?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                HStack(spacing: HelmSpacing.sm) {
                    Text(model.statusLabel)
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                    Text(model.copyRegisterLabel)
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                }

                Text(model.headline)
                    .helmType(.label)

                Text(model.body)
                    .helmType(.body, color: HelmColor.fgSecondary)

                HStack(alignment: .firstTextBaseline, spacing: HelmSpacing.md) {
                    readout(label: "N", value: "\(model.nExp)/\(model.nCtrl)")
                    if let cliffsDelta = model.cliffsDelta {
                        readout(label: "δ", value: String(format: "%+.2f", cliffsDelta))
                    }
                    if let medianDelta = model.medianDelta {
                        readout(label: "MED", value: String(format: "%+.1f", medianDelta))
                    }
                }

                if model.canConfirmToMemory, let onConfirmToMemory {
                    Button("Save to Memory") {
                        CoachApplyMomentStore.shared.play()
                        onConfirmToMemory()
                    }
                    .buttonStyle(.helmSecondary)
                }
            }
        }
    }

    private func readout(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text(label)
                .helmType(.monoTag, color: HelmColor.fgMuted)
            Text(value)
                .helmType(.number)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
}

#Preview("Pattern finding emerging") {
    PatternFindingCard(
        model: PatternFindingCardModel(
            id: "alcohol_worse_sleep",
            statusLabel: "EMERGING",
            copyRegisterLabel: "TENTATIVE",
            headline: "Starting to notice alcohol days and sleep duration",
            body: "Association language only. More days will firm this up. Median shift -18.00 min. n=14/22.",
            nExp: 14,
            nCtrl: 22,
            cliffsDelta: -0.32,
            medianDelta: -18,
            canConfirmToMemory: true
        ),
        onConfirmToMemory: {}
    )
    .helmScreenPadding()
    .helmTheme()
}
