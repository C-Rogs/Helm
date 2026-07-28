import DesignSystem
import SwiftUI

struct RecoveryDetailView: View {
    let model: RecoveryDetailModel
    let historyPoints: [ReadinessHistoryPoint]
    var matchedCardNamespace: Namespace.ID?
    var onAskCoach: ((String) -> Void)?

    var body: some View {
        ScrollView {
            HelmScreenStack {
                narrationCard
                    .helmStaggeredAppear(index: 0)

                scoreCard
                    .helmStaggeredAppear(index: 1)

                ReadinessHistoryChartCard(
                    points: historyPoints,
                    showsBandOverlay: true,
                    baselineNights: model.validNights < 14 ? model.validNights : nil,
                    title: "Readiness history",
                    subtitle: "ARC score with target bands"
                )
                .helmStaggeredAppear(index: 2)

                contributorsCard
                    .helmStaggeredAppear(index: 3)

                if model.isCoachHandoffEnabled, let onAskCoach {
                    AskCoachBar(prompt: "Ask coach about this") {
                        onAskCoach(model.coachPrompt)
                    }
                    .helmStaggeredAppear(index: 4)
                }
            }
            .helmScreenPadding()
        }
        .helmScreenBackground()
        .navigationTitle("Recovery")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var narrationCard: some View {
        BriefCard(
            eyebrow: "Coach read",
            citationLabel: model.citationLabel,
            narration: model.narration,
            isEngineOnly: model.isEngineOnly
        )
    }

    private var scoreCard: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                HelmSectionEyebrow("ARC")

                HStack(alignment: .firstTextBaseline, spacing: HelmSpacing.xs) {
                    HelmNumericText(model.score)
                        .helmType(.heroNumber, color: HelmColor.color(for: model.helmState))
                    Text(model.helmState.label)
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                DeviationBand(
                    label: "Target band",
                    value: Double(model.score),
                    band: model.targetBand,
                    unit: "pts",
                    state: model.helmState,
                    verdictTag: model.helmState.label.uppercased(),
                    layout: .inline,
                    decimalPlaces: 0
                )

                if model.validNights < 14 {
                    Text("Provisional baseline (\(model.validNights)/14 nights)")
                        .helmType(.body, color: HelmColor.fgMuted)
                }
            }
        }
        .skinAccentStripe(HelmColor.color(for: model.helmState))
    }

    private var contributorsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                HelmSectionEyebrow("CONTRIBUTORS")

                ForEach(model.contributors) { contributor in
                    DeviationBand(
                        label: contributor.label,
                        value: contributor.value,
                        band: contributor.band,
                        unit: contributor.unit,
                        state: contributor.state,
                        verdictTag: contributor.verdictTag,
                        decimalPlaces: contributor.decimalPlaces,
                        isValueAvailable: contributor.isValueAvailable
                    )

                    if contributor.id != model.contributors.last?.id {
                        HelmHairlineRule()
                    }
                }
            }
        }
    }
}

private struct MatchedCardModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.helmMatchedCardDetail(id: id, in: namespace, isSource: false)
        } else {
            content
        }
    }
}

#if DEBUG
#Preview("Recovery good") {
    NavigationStack {
        RecoveryDetailView(
            model: .goodFixture,
            historyPoints: TrendChartFixtures.readinessHistory
        ) { _ in }
    }
    .helmTheme()
}

#Preview("Recovery compromised") {
    NavigationStack {
        RecoveryDetailView(
            model: .compromisedFixture,
            historyPoints: TrendChartFixtures.readinessHistory
        ) { _ in }
    }
    .helmTheme()
}

#Preview("Recovery cold start") {
    NavigationStack {
        RecoveryDetailView(
            model: .coldStartFixture,
            historyPoints: Array(TrendChartFixtures.readinessHistory.prefix(2))
        ) { _ in }
    }
    .helmTheme()
}

#Preview("Recovery offline") {
    NavigationStack {
        RecoveryDetailView(
            model: .offlineFixture,
            historyPoints: TrendChartFixtures.readinessHistory
        )
    }
    .helmTheme()
}

#Preview("Recovery accessibility") {
    NavigationStack {
        RecoveryDetailView(
            model: .goodFixture,
            historyPoints: TrendChartFixtures.readinessHistory
        ) { _ in }
    }
    .helmTheme()
    .dynamicTypeSize(.accessibility5)
}
#endif
