import CoachLLM
import DesignSystem
import HealthKitIngest
import PlanKit
import SwiftUI

/// Card grid of generated plan options with outcome, benefits, and challenges.
struct PlanOptionCardsView: View {
    let options: [PlanBuilderOption]
    let onSelect: (PlanBuilderOption) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                Text("Ways this block could go. Pick one to refine.")
                    .helmType(.body, color: HelmColor.fgSecondary)

                ForEach(options) { option in
                    card(option)
                }
            }
            .padding(HelmSpacing.screenGutter)
        }
    }

    private func card(_ option: PlanBuilderOption) -> some View {
        Button {
            onSelect(option)
        } label: {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                Text(option.candidate.headline)
                    .helmType(.title, color: HelmColor.fg)

                Text(option.copy.outcome)
                    .helmType(.body, color: HelmColor.fg)

                statRow(option.candidate)

                if !option.copy.benefits.isEmpty {
                    bulletList("Benefits", items: option.copy.benefits, icon: "plus.circle", color: HelmColor.positive)
                }

                if !option.copy.challenges.isEmpty {
                    bulletList("Challenges", items: option.copy.challenges, icon: "minus.circle", color: HelmColor.fgMuted)
                }

                if !option.copy.sources.isEmpty {
                    Text("Sources: \(option.copy.sources.joined(separator: ", "))")
                        .font(HelmTypography.caption)
                        .foregroundStyle(HelmColor.fgMuted)
                }

                Text("Refine this plan")
                    .helmType(.label, color: HelmColor.accent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(HelmSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HelmColor.surface, in: RoundedRectangle(cornerRadius: HelmRadius.card))
            .overlay {
                RoundedRectangle(cornerRadius: HelmRadius.card)
                    .strokeBorder(HelmColor.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.helmPressableCard)
    }

    private func statRow(_ candidate: CandidatePlan) -> some View {
        HStack(spacing: HelmSpacing.md) {
            StatChip(label: "SESSIONS / WEEK", value: "\(candidate.daysPerWeek)")
            StatChip(label: "MINUTES", value: "\(candidate.sessionDurationMinutes)")
            StatChip(label: "DELOAD", value: "every \(candidate.deloadCadenceWeeks) wk")
        }
    }

    private func bulletList(_ title: String, items: [String], icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text(title)
                .helmType(.label, color: HelmColor.fgSecondary)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: HelmSpacing.xs) {
                    Image(systemName: icon)
                        .font(.caption2)
                        .foregroundStyle(color)
                    Text(item)
                        .helmType(.body, color: HelmColor.fgSecondary)
                }
            }
        }
    }
}

#Preview {
    PlanOptionCardsView(
        options: [
            PlanBuilderOption(
                candidate: CandidatePlan(
                    id: "demo",
                    headline: "Push / Pull / Legs rotation",
                    programTemplateRaw: "ppl",
                    daysPerWeek: 3,
                    sessionDurationMinutes: 60,
                    weeklyPeakSetsByMuscle: [.chest: 12],
                    frequencyByMuscle: [.chest: 1],
                    deloadCadenceWeeks: 5,
                    availabilityFitScore: 1.0,
                    leverNotes: []
                ),
                copy: PlanOptionCardCopy(
                    candidateID: "demo",
                    outcome: "Steady growth on three focused sessions.",
                    benefits: ["Classic split, easy scheduling", "High per-session focus"],
                    challenges: ["Each muscle hit only weekly"]
                )
            )
        ],
        onSelect: { _ in }
    )
    .helmTheme()
    .helmScreenBackground()
}
