import Core
import DesignSystem
import HealthKitIngest
import SwiftUI

struct TrainingWeekReviewSheet: View {
    let progression: ProgressionDetailModel
    let weekAhead: WeekAheadScheduleModel?
    let pendingReactiveDeload: Bool
    var onGotIt: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var behindMuscles: [MesocycleMuscleRow] {
        progression.muscles.filter { $0.scheduledRemaining > 0.5 }
    }

    private var nextSessions: [WeekAheadScheduleRow] {
        guard let weekAhead else { return [] }
        return weekAhead.chronologicalRows.filter { row in
            !row.isRestDay
                && (row.status == .today
                    || row.status == .upcoming
                    || row.status == .shifted)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                HelmScreenStack {
                    summaryCard.helmStaggeredAppear(index: 0)
                    volumeCard.helmStaggeredAppear(index: 1)
                    if !behindMuscles.isEmpty {
                        behindCard.helmStaggeredAppear(index: 2)
                    }
                    if showsDeloadHint {
                        deloadCard.helmStaggeredAppear(index: 3)
                    }
                    if !nextSessions.isEmpty {
                        nextSessionsCard.helmStaggeredAppear(index: 4)
                    }

                    Button("Got it") {
                        onGotIt()
                        dismiss()
                    }
                    .buttonStyle(.helmPrimary)
                    .helmStaggeredAppear(index: 5)

                    NavigationLink {
                        ProgressionDetailContainer()
                    } label: {
                        Text("Open progression")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.helmSecondary)
                    .helmStaggeredAppear(index: 6)
                }
                .helmScreenPadding()
                .padding(.bottom, HelmLayout.trainScrollBottomInset)
            }
            .helmScreenBackground()
            .navigationTitle("Training week review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var showsDeloadHint: Bool {
        progression.isDeloadWeek || pendingReactiveDeload
    }

    private var summaryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                HelmSectionEyebrow("SCHEDULE WEEK")
                Text(progression.blockSummary)
                    .helmType(.title)
                Text(progression.coachSummary)
                    .helmType(.body, color: HelmColor.fgSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if progression.isDeloadWeek {
                    Text("Deload")
                        .helmType(.monoTag, color: HelmColor.ready)
                        .padding(.horizontal, HelmSpacing.xs)
                        .padding(.vertical, HelmSpacing.xxs)
                        .background(HelmColor.ready.opacity(0.12), in: Capsule())
                }
            }
        }
        .skinAccentStripe(progression.isDeloadWeek ? HelmColor.ready : HelmColor.accent)
    }

    private var volumeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                HelmSectionEyebrow("VOLUME")
                if progression.muscles.isEmpty {
                    Text("No mesocycle state yet. Finish training plan setup in Settings.")
                        .helmType(.body, color: HelmColor.fgMuted)
                } else {
                    ForEach(progression.muscles) { muscle in
                        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                            HStack {
                                Text(muscle.label).helmType(.label)
                                Spacer()
                                Text(muscle.phaseLabel)
                                    .helmType(.monoTag, color: HelmColor.fgMuted)
                            }
                            LandmarkVolumeBar(
                                label: "Sets",
                                weeklySets: muscle.weeklyDone,
                                scheduledSets: muscle.scheduledRemaining,
                                mev: muscle.mev,
                                mrv: muscle.mrv,
                                state: muscle.state
                            )
                            Text(muscle.volumeReadout)
                                .helmType(.body, color: HelmColor.fgMuted)
                        }
                        if muscle.id != progression.muscles.last?.id {
                            HelmHairlineRule()
                        }
                    }
                    Text("Solid = logged · Tint = remaining to weekly target · Scale = 0 / MEV / MRV")
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                }
            }
        }
    }

    private var behindCard: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                HelmSectionEyebrow("BEHIND TARGET")
                ForEach(behindMuscles) { muscle in
                    HStack {
                        Text(muscle.label).helmType(.label)
                        Spacer()
                        Text("\(Int(muscle.scheduledRemaining.rounded())) sets")
                            .helmType(.monoTag, color: HelmColor.primed)
                    }
                }
            }
        }
    }

    private var deloadCard: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                HelmSectionEyebrow("DELOAD")
                if progression.isDeloadWeek {
                    Text("Deload week is active. Keep form sharp; volume and load stay light on purpose.")
                        .helmType(.body, color: HelmColor.fgSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if pendingReactiveDeload {
                    Text(
                        "Engine proposes a reactive deload week. Confirm or dismiss under Settings, Training plan. Nothing changes until you confirm."
                    )
                    .helmType(.body, color: HelmColor.fgSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .skinAccentStripe(HelmColor.ready)
    }

    private var nextSessionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                HelmSectionEyebrow("NEXT SESSIONS")
                ForEach(nextSessions) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.dayLabel).helmType(.label)
                        Spacer()
                        Text(row.splitLabel)
                            .helmType(.body, color: HelmColor.fgSecondary)
                        if let status = row.statusLabel {
                            Text(status)
                                .helmType(.monoTag, color: HelmColor.fgMuted)
                        }
                    }
                    if row.id != nextSessions.last?.id {
                        HelmHairlineRule()
                    }
                }
            }
        }
    }
}

struct TrainingWeekReviewLoader: View {
    let weekAhead: WeekAheadScheduleModel?
    var onGotIt: () -> Void

    @State private var progression: ProgressionDetailModel?
    @State private var pendingReactiveDeload = false

    var body: some View {
        Group {
            if let progression {
                TrainingWeekReviewSheet(
                    progression: progression,
                    weekAhead: weekAhead,
                    pendingReactiveDeload: pendingReactiveDeload,
                    onGotIt: onGotIt
                )
            } else {
                NavigationStack {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .helmScreenBackground()
                        .navigationTitle("Training week review")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium])
            }
        }
        .task { await load() }
    }

    @MainActor
    private func load() async {
        let readiness = ReadinessBootstrap.readinessService.state.score
        do {
            progression = try await ProgressionDetailBuilder.load(
                store: PersistenceBootstrap.persistenceStore,
                engine: PlanBootstrap.engine,
                readiness: readiness
            )
        } catch {
            progression = ProgressionDetailBuilder.coldStartFallback()
        }
        pendingReactiveDeload =
            (try? await PlanBootstrap.prescriptionService.pendingReactiveDeload()) ?? false
    }
}

#if DEBUG
#Preview("Week review mid-meso") {
    TrainingWeekReviewSheet(
        progression: .midMesoFixture,
        weekAhead: .weekAheadFixture,
        pendingReactiveDeload: false,
        onGotIt: {}
    )
    .helmTheme()
}

#Preview("Week review deload pending") {
    TrainingWeekReviewSheet(
        progression: .deloadWeekFixture,
        weekAhead: .weekAheadFixture,
        pendingReactiveDeload: true,
        onGotIt: {}
    )
    .helmTheme()
}
#endif
