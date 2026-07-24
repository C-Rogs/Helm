import DesignSystem
import SwiftUI

struct ProgressionDetailView: View {
    let model: ProgressionDetailModel
    var matchedCardNamespace: Namespace.ID? = nil

    var body: some View {
        ScrollView {
            HelmScreenStack {
                blockCard.helmStaggeredAppear(index: 0)
                mesocycleCard.helmStaggeredAppear(index: 1)
                schemeCard.helmStaggeredAppear(index: 2)
                laddersSection.helmStaggeredAppear(index: 3)
            }
            .helmScreenPadding()
        }
        .helmScreenBackground()
        .navigationTitle("Progression")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var blockCard: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                HStack {
                    HelmSectionEyebrow("BLOCK")
                    Spacer()
                    if model.isDeloadWeek {
                        Text("Deload")
                            .helmType(.monoTag, color: HelmColor.ready)
                            .padding(.horizontal, HelmSpacing.xs)
                            .padding(.vertical, HelmSpacing.xxs)
                            .background(HelmColor.ready.opacity(0.12), in: Capsule())
                    }
                }
                .modifier(MatchedCardModifier(id: "plan-progression", namespace: matchedCardNamespace))

                Text(model.phaseLabel).helmType(.title)

                HStack(spacing: HelmSpacing.sm) {
                    Text(model.blockSummary).helmType(.body, color: HelmColor.fgSecondary)
                    Text("·").helmType(.body, color: HelmColor.fgMuted)
                    Text(model.experienceLabel).helmType(.monoTag, color: HelmColor.fgMuted)
                }

                if model.isColdStart {
                    Text("Log working sets to populate lift ladders.")
                        .helmType(.body, color: HelmColor.fgMuted)
                }
            }
        }
        .skinAccentStripe(model.isDeloadWeek ? HelmColor.ready : HelmColor.accent)
    }

    private var mesocycleCard: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                HelmSectionEyebrow("MESOCYCLE")
                if model.muscles.isEmpty {
                    Text("No mesocycle state yet. Finish training plan setup in Settings.")
                        .helmType(.body, color: HelmColor.fgMuted)
                } else {
                    ForEach(model.muscles) { muscle in
                        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                            HStack {
                                Text(muscle.label).helmType(.label)
                                Spacer()
                                Text("W\(muscle.currentWeek)/\(muscle.blockLengthWeeks)")
                                    .helmType(.monoTag, color: HelmColor.fgMuted)
                                Text(muscle.phaseLabel).helmType(.monoTag, color: HelmColor.fgMuted)
                            }
                            LandmarkVolumeBar(
                                label: "Sets",
                                weeklySets: muscle.weeklyDone,
                                mev: muscle.mev,
                                mrv: muscle.mrv,
                                state: muscle.state
                            )
                            Text("Target \(muscle.weeklyTarget) hard sets this week")
                                .helmType(.body, color: HelmColor.fgMuted)
                        }
                        if muscle.id != model.muscles.last?.id { HelmHairlineRule() }
                    }
                }
            }
        }
    }

    private var schemeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                HelmSectionEyebrow("PROGRESSION SCHEME")
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: HelmSpacing.sm
                ) {
                    StatChip(label: "Rep range", value: model.scheme.repRange)
                    StatChip(label: "RPE cap", value: model.scheme.rpeCap)
                    StatChip(label: "Target RPE", value: model.scheme.targetRPE)
                    StatChip(label: "Load bump", value: model.scheme.loadIncrement)
                }
                Text(model.scheme.setsPerSession).helmType(.body, color: HelmColor.fgMuted)
            }
        }
    }

    @ViewBuilder
    private var laddersSection: some View {
        if model.ladders.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                    HelmSectionEyebrow("LIFT LADDERS")
                    Text("Complete working sets to build per-lift e1RM ladders.")
                        .helmType(.body, color: HelmColor.fgMuted)
                }
            }
        } else {
            ForEach(model.ladders) { ladderCard($0) }
        }
    }

    private func ladderCard(_ ladder: LiftLadderRow) -> some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ladder.displayName).helmType(.label)
                    Spacer()
                    if let e1rm = ladder.currentE1RMKilograms {
                        HStack(spacing: HelmSpacing.xxs) {
                            HelmNumericText(e1rm, format: "%.0f").helmType(.number, color: HelmColor.accent)
                            Text("kg e1RM").helmType(.monoTag, color: HelmColor.fgMuted)
                        }
                    }
                }
                Text(ladder.targetRepRange).helmType(.monoTag, color: HelmColor.fgMuted)
                if ladder.steps.isEmpty {
                    Text("No logged steps yet.").helmType(.body, color: HelmColor.fgMuted)
                } else {
                    ForEach(ladder.steps) { step in
                        ladderStepRow(step)
                        if step.id != ladder.steps.last?.id { HelmHairlineRule() }
                    }
                }
            }
        }
    }

    private func ladderStepRow(_ step: LiftLadderStep) -> some View {
        HStack(alignment: .top, spacing: HelmSpacing.sm) {
            Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(step.isCompleted ? HelmColor.ready : HelmColor.fgMuted)
                .font(.body.weight(.semibold))
                .frame(width: HelmSpacing.lg)
            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                Text(step.title)
                    .helmType(.body, color: step.isCompleted ? HelmColor.fg : HelmColor.fgSecondary)
                HStack(spacing: HelmSpacing.sm) {
                    if let achievedAtLabel = step.achievedAtLabel {
                        Text(achievedAtLabel).helmType(.monoTag, color: HelmColor.fgMuted)
                    }
                    if let delta = step.deltaKilograms, delta > 0 {
                        Text("+\(String(format: "%.1f", delta)) kg")
                            .helmType(.monoTag, color: HelmColor.primed)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct MatchedCardModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID?
    func body(content: Content) -> some View {
        if let namespace {
            content.helmMatchedCardDetail(id: id, in: namespace, isSource: false)
        } else { content }
    }
}

#if DEBUG
#Preview("Progression mid-meso") {
    NavigationStack { ProgressionDetailView(model: .midMesoFixture) }.helmTheme()
}
#Preview("Progression deload") {
    NavigationStack { ProgressionDetailView(model: .deloadWeekFixture) }.helmTheme()
}
#Preview("Progression cold start") {
    NavigationStack { ProgressionDetailView(model: .coldStartFixture) }.helmTheme()
}
#endif
