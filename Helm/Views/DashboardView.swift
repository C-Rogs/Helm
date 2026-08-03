import Core
import DesignSystem
import Foundation
import HealthKitIngest
import NutritionKit
import Persistence
import ReadinessKit
import SwiftUI

struct DashboardView: View {
    private var readinessService: ReadinessService { ReadinessBootstrap.readinessService }
    private var prescriptionService: PrescriptionService { PlanBootstrap.prescriptionService }
    private var briefService: BriefService { BriefBootstrap.briefService }
    private var nutritionService: NutritionService { NutritionBootstrap.nutritionService }
    @Bindable private var chatController = ChatBootstrap.controller
    @Bindable private var muscleVolumeStore = MuscleVolumeBootstrap.store
    private var thresholdInsightService: ThresholdInsightService { ProactiveBootstrap.thresholdInsightService }

    @Environment(\.helmReduceMotion) private var reduceMotion
    @State private var revealStore = ReadinessRevealStore()
    @State private var contributorDetailsVisible = true
    @State private var sleepSummary: SleepNightSummary?
    @Namespace private var readinessNamespace
    @Namespace private var prescriptionNamespace
    @Namespace private var muscleVolumeNamespace

    private var today: HelmDay {
        HelmDay.day(for: .now, calendar: .current)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                HelmScreenStack {
                    greetingHeader
                        .helmStaggeredAppear(index: 0)
                    thresholdInsightCard
                        .helmStaggeredAppear(index: 1)
                    briefCard
                        .helmStaggeredAppear(index: 2)
                    readinessCard
                        .helmStaggeredAppear(index: 3)
                    sleepCard
                        .helmStaggeredAppear(index: 4)
                    prescriptionCard
                        .helmStaggeredAppear(index: 5)
                    muscleVolumeSummaryCard
                        .helmStaggeredAppear(index: 6)
                    nutritionTargetsCard
                        .helmStaggeredAppear(index: 7)
                    DashboardTrendsSection()
                        .helmStaggeredAppear(index: 8)

                    Button {
                        chatController.requestCoachHandoff(prompt: "What should I focus on today?")
                    } label: {
                        Label("Ask Coach", helmIcon: .chat, context: .inline)
                    }
                    .buttonStyle(.helmSecondary)
                    .helmStaggeredAppear(index: 9)
                }
                .helmScreenPadding()
            }
            .helmScreenBackground()
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await readinessService.refresh()
                await loadSleepSummary()
                await prescriptionService.refresh(readiness: readinessService.state.score)
                await nutritionService.refresh(
                    prescriptionSummary: prescriptionService.state.summary
                )
                await briefService.refresh(
                    readiness: readinessService.state.score,
                    prescriptionSummary: prescriptionService.state.summary
                )
                await ProactiveBootstrap.refreshThresholdInsights()
                muscleVolumeStore.refresh()
            }
            .onChange(of: readinessService.state) { _, newState in
                Task {
                    await loadSleepSummary()
                    await prescriptionService.refresh(readiness: newState.score)
                    await nutritionService.refresh(
                        prescriptionSummary: prescriptionService.state.summary
                    )
                    await briefService.refresh(
                        readiness: newState.score,
                        prescriptionSummary: prescriptionService.state.summary
                    )
                    await ProactiveBootstrap.refreshThresholdInsights()
                }
            }
            .onChange(of: prescriptionService.state) { _, newState in
                Task {
                    await nutritionService.refresh(prescriptionSummary: newState.summary)
                    await briefService.refresh(
                        readiness: readinessService.state.score,
                        prescriptionSummary: newState.summary
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var sleepCard: some View {
        if let sleepSummary {
            NavigationLink {
                SleepAnalysisContainer()
            } label: {
                DashboardSleepCard(
                    summary: sleepSummary,
                    showsChevron: true
                )
            }
            .buttonStyle(.helmPressableCard)
        }
    }

    private func loadSleepSummary() async {
        let wakeDay = Calendar.current.startOfDay(for: Date())
        do {
            sleepSummary = try PersistenceBootstrap.persistenceStore.sleep.nightSummary(
                forWakeCalendarDay: wakeDay
            )
        } catch {
            sleepSummary = nil
        }
    }

    @ViewBuilder
    private var thresholdInsightCard: some View {
        if let insight = thresholdInsightService.currentInsight {
            ThresholdInsightCard(insight: insight)
        }
    }

    @ViewBuilder
    private var briefCard: some View {
        switch briefService.state {
        case .loading:
            HelmSkeletonCard(rowCount: 2)
        case let .ready(model):
            briefShell(
                narration: model.narration,
                isEngineOnly: model.isEngineOnly,
                citationLabel: model.citationLabel
            )
        }
    }

    private func briefShell(narration: String, isEngineOnly: Bool, citationLabel: String?) -> some View {
        BriefCard(
            citationLabel: citationLabel,
            narration: narration,
            isEngineOnly: isEngineOnly
        )
    }

    @ViewBuilder
    private var muscleVolumeSummaryCard: some View {
        if muscleVolumeStore.isLoading, muscleVolumeStore.model == nil {
            HelmSkeletonCard(rowCount: 3)
        } else if let model = muscleVolumeStore.model {
            NavigationLink {
                MuscleVolumeBoardContainer()
            } label: {
                MuscleVolumeSummaryCard(model: model)
                    .helmMatchedCardDetail(id: "muscle-volume", in: muscleVolumeNamespace)
            }
            .buttonStyle(.helmPressableCard)
        }
    }

    @ViewBuilder
    private var prescriptionCard: some View {
        switch prescriptionService.state {
        case .loading:
            HelmSkeletonCard(rowCount: 3)
        case .awaitingCatalog:
            prescriptionShell(subtitle: "Awaiting exercise catalog") {
                Text("Import exercises from Settings or finish first launch seeding.")
                    .helmType(.body, color: HelmColor.fgMuted)
                    .multilineTextAlignment(.leading)
            }
        case let .prescribed(summary):
            NavigationLink {
                ProgressionDetailContainer(matchedCardNamespace: prescriptionNamespace)
            } label: {
                VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                    HelmSectionEyebrow("TODAY'S SESSION")

                    SessionDesignedCard(
                        title: summary.title,
                        summary: summary.summary,
                        rationale: summary.rationale,
                        onCoach: {
                            chatController.requestCoachHandoff(prompt: summary.coachPromptSeed)
                            AppTabRouter.shared.openTrain()
                            TrainBootstrap.sessionController.discussTodaysSession()
                        },
                        onRegenerate: {
                            Task { await TrainBootstrap.sessionController.regenerateTodaysPrescription() }
                        }
                    ) {
                        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                            if summary.readinessAdjusted {
                                Text("Volume trimmed for readiness")
                                    .helmType(.monoTag, color: HelmColor.depleted)
                            }

                            SessionExercisePreviewList(
                                exercises: summary.exercises.map(\.displayName)
                            )

                            HStack {
                                HStack(spacing: HelmSpacing.xxs) {
                                    HelmNumericText(summary.totalSets)
                                    Text("total sets")
                                        .helmType(.body, color: HelmColor.fgSecondary)
                                }
                                Spacer()
                                Text(summary.phase.label)
                                    .helmType(.monoTag, color: HelmColor.fgMuted)
                                HelmIconView(.chevronRight, context: .inline)
                                    .foregroundStyle(HelmColor.fgMuted)
                            }
                            .explainable(
                                ExplainableMetricMappers.prescriptionVolume(
                                    summary,
                                    baselineSets: estimatedBaselineSets(for: summary),
                                    coachAvailable: chatController.isCoachAvailable
                                ),
                                onAskCoach: chatController.requestCoachHandoff(prompt:)
                            )
                        }
                    }
                }
                .helmMatchedCardDetail(id: "plan-progression", in: prescriptionNamespace)
            }
            .buttonStyle(.helmPressableCard)
        }
    }

    private func prescriptionShell<Content: View>(
        subtitle: String,
        phase: TrainingPhase? = nil,
        showsChevron: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                HStack {
                    HelmSectionEyebrow("TODAY'S SESSION")
                    Spacer()
                    if let phase {
                        Text(phase.label)
                            .helmType(.monoTag, color: HelmColor.accent)
                            .padding(.horizontal, HelmSpacing.xs)
                            .padding(.vertical, HelmSpacing.xxs)
                            .background(HelmColor.accent.opacity(0.12), in: Capsule())
                    }
                    if showsChevron {
                        HelmIconView(.chevronRight, context: .inline)
                            .foregroundStyle(HelmColor.fgMuted)
                    }
                }

                content()

                Text(subtitle)
                    .helmType(.body, color: HelmColor.fgMuted)
            }
        }
    }

    private func prescriptionExerciseRow(_ exercise: PrescribedExerciseSummary) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text(exercise.displayName)
                .helmType(.body)
            HStack(spacing: HelmSpacing.sm) {
                Text("\(exercise.targetSets) × \(exercise.targetRepRange)")
                    .helmType(.body, color: HelmColor.fgSecondary)
                if let load = exercise.targetLoad {
                    Text(load)
                        .helmType(.body, color: HelmColor.fgSecondary)
                }
                if let rpe = exercise.targetRPE {
                    Text(rpe)
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                }
            }
        }
        .padding(.vertical, HelmSpacing.xxs)
    }

    private func prescriptionSubtitle(for summary: PrescribedSessionSummary) -> String {
        var parts = ["\(summary.exercises.count) exercises"]
        if let label = TrainingPlanCoachContext.emphasisDisplayLabel(summary.emphasis) {
            parts.append(label)
        }
        return parts.joined(separator: " · ")
    }

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text(greetingText)
                .helmType(.title)
            Text("Today's readiness")
                .helmType(.body, color: HelmColor.fgSecondary)
        }
    }

    @ViewBuilder
    private var readinessCard: some View {
        switch readinessService.state {
        case .loading:
            readinessShell(subtitle: "Loading") {
                VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                    HelmSkeletonBlock(height: 120)
                        .frame(maxWidth: 220)
                        .frame(maxWidth: .infinity)
                    HelmSkeletonBlock(height: 12)
                    HelmSkeletonBlock(height: 12)
                }
            }
        case .awaitingData:
            readinessShell(subtitle: "Awaiting data") {
                placeholderArc(state: .compromised, subtitle: "Awaiting data")
            }
        case let .buildingBaseline(_, message):
            readinessShell(subtitle: message) {
                placeholderArc(state: .compromised, subtitle: message)
            }
        case let .scored(score):
            scoredReadinessCard(score: score)
        }
    }

    private func scoredReadinessCard(score: ReadinessScore) -> some View {
        let helmState = HelmState.readiness(score: Double(score.score))
        let shouldReveal = revealStore.shouldReveal(for: today)

        return NavigationLink {
            RecoveryDetailContainer(
                score: score,
                matchedCardNamespace: readinessNamespace
            )
        } label: {
            readinessShell(
                subtitle: readinessSubtitle(for: score),
                state: helmState
            ) {
                VStack(alignment: .leading, spacing: HelmSpacing.md) {
                    ArcRevealGauge(
                        targetValue: Double(score.score),
                        state: helmState,
                        reveal: shouldReveal,
                        reduceMotion: reduceMotion,
                        detailsVisible: $contributorDetailsVisible,
                        onRevealStart: {
                            HapticEngine.shared.play(.readinessReveal)
                            revealStore.markRevealed(for: today)
                        }
                    ) { displayValue in
                        VStack(spacing: HelmSpacing.xxs) {
                            HelmNumericText(Int(displayValue.rounded()))
                                .helmType(.heroNumber, color: HelmColor.color(for: helmState))
                            Text(helmState.label)
                                .helmType(.monoTag, color: HelmColor.fgMuted)
                            Text(confidenceLabel(for: score.confidence))
                                .helmType(.body, color: HelmColor.fgMuted)
                        }
                    }
                    .frame(maxWidth: 220)
                    .frame(maxWidth: .infinity)
                    .helmMatchedCardDetail(id: "arc-readiness", in: readinessNamespace)
                    .onAppear {
                        contributorDetailsVisible = !shouldReveal
                    }

                    contributorsSection(for: score, visible: contributorDetailsVisible)
                        .readinessDetailsReveal(visible: contributorDetailsVisible, reduceMotion: reduceMotion)
                }
            }
        }
        .buttonStyle(.helmPressableCard)
    }

    private func placeholderArc(state: HelmState, subtitle: String) -> some View {
        ArcGauge(value: 0, state: state) {
            VStack(spacing: HelmSpacing.xxs) {
                Text("--")
                    .helmType(.heroNumber, color: HelmColor.fgMuted)
                Text(state.label)
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                Text(subtitle)
                    .helmType(.body, color: HelmColor.fgMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: 220)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func readinessShell<Content: View>(
        subtitle: String,
        state: HelmState? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let card = Card {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                HStack {
                    HelmSectionEyebrow("ARC")
                    Spacer()
                    if let state {
                        stateBadge(for: state)
                    }
                }

                content()

                Text(subtitle)
                    .helmType(.body, color: HelmColor.fgMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }

        if let state {
            card.skinAccentStripe(HelmColor.color(for: state))
        } else {
            card
        }
    }

    private func contributorsSection(for score: ReadinessScore, visible: Bool) -> some View {
        var contributors: [(String, Double?)] = [
            ("HRV", score.contributors.zHRV),
            ("Resting HR", score.contributors.zRestingHR),
            ("Sleep", score.contributors.zSleep),
        ]
        if score.contributors.zStrain != nil {
            contributors.append(("Strain", score.contributors.zStrain))
        }
        if score.contributors.zRespiratory != nil {
            contributors.append(("Respiratory", score.contributors.zRespiratory))
        }
        if score.contributors.zTemperature != nil {
            contributors.append(("Temperature", score.contributors.zTemperature))
        }

        return VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            HelmHairlineRule()

            Text("Contributors")
                .helmType(.label)
                .padding(.top, HelmSpacing.sm)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: HelmSpacing.sm),
                    GridItem(.flexible(), spacing: HelmSpacing.sm),
                ],
                spacing: HelmSpacing.sm
            ) {
                ForEach(Array(contributors.enumerated()), id: \.offset) { index, contributor in
                    contributorChip(contributor.0, z: contributor.1)
                        .readinessContributorReveal(
                            visible: visible,
                            index: index,
                            reduceMotion: reduceMotion
                        )
                }
            }
        }
    }

    private func contributorChip(_ label: String, z: Double?) -> StatChip {
        StatChip(
            label: label,
            value: contributorValueText(z),
            state: contributorState(z)
        )
    }

    private func contributorState(_ z: Double?) -> HelmState? {
        guard let z else { return nil }
        if z > 0.75 { return .primed }
        if z < -0.75 { return .depleted }
        return .ready
    }

    private func stateBadge(for state: HelmState) -> some View {
        Text(state.label)
            .helmType(.monoTag, color: HelmColor.color(for: state))
            .padding(.horizontal, HelmSpacing.xs)
            .padding(.vertical, HelmSpacing.xxs)
            .background(HelmColor.color(for: state).opacity(0.15), in: Capsule())
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5 ..< 12: return "Good morning"
        case 12 ..< 17: return "Good afternoon"
        case 17 ..< 22: return "Good evening"
        default: return "Good night"
        }
    }

    private func readinessSubtitle(for score: ReadinessScore) -> String {
        if score.validNights < 14 {
            return "Provisional baseline (\(score.validNights)/14 nights)"
        }
        return "\(HelmState.readiness(score: Double(score.score)).label) · \(confidenceLabel(for: score.confidence))"
    }

    private func confidenceLabel(for confidence: ReadinessConfidence) -> String {
        switch confidence {
        case .high: "High confidence"
        case .medium: "Medium confidence"
        case .low: "Low confidence"
        }
    }

    private func contributorValueText(_ z: Double?) -> String {
        guard let z else { return "N/A" }
        let sign = z >= 0 ? "+" : ""
        return "z \(sign)\(String(format: "%.1f", z))"
    }

    @ViewBuilder
    private var nutritionTargetsCard: some View {
        switch nutritionService.state {
        case .loading:
            nutritionNavigationLink {
                VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                    HelmSkeletonBlock(height: 28)
                    HelmSkeletonBlock(height: 12)
                    HStack(spacing: HelmSpacing.md) {
                        HelmSkeletonBlock()
                            .frame(maxWidth: .infinity)
                        HelmSkeletonBlock()
                            .frame(maxWidth: .infinity)
                        HelmSkeletonBlock()
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        case let .ready(snapshot):
            nutritionNavigationLink {
                compactNutritionContent(snapshot: snapshot)
            }
        }
    }

    private func nutritionNavigationLink<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button {
            AppTabRouter.shared.openNutrition()
        } label: {
            nutritionCardShell {
                content()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.helmPressableCard)
    }

    private func nutritionCardShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                HStack {
                    HelmSectionEyebrow("NUTRITION", showsArcMark: false)
                    Spacer()
                    HelmIconView(.chevronRight, context: .inline)
                        .foregroundStyle(HelmColor.fgMuted)
                }
                content()
            }
        }
    }

    @ViewBuilder
    private func compactNutritionContent(snapshot: NutritionDaySnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: HelmSpacing.xs) {
            HelmNumericText(snapshot.targets.caloriesKcal)
                .helmType(.bigNumber)
            Text("kcal target")
                .helmType(.body, color: HelmColor.fgMuted)
            Spacer()
            Text(snapshot.dayType.rawValue.capitalized)
                .helmType(.monoTag, color: HelmColor.fgMuted)
        }

        if let actualCalories = snapshot.actual?.totalEnergy.map({ Int($0.kilocalories.rounded()) }) {
            HStack(spacing: HelmSpacing.xxs) {
                HelmNumericText(actualCalories)
                Text("kcal logged")
                    .helmType(.body, color: HelmColor.fgSecondary)
            }
        } else {
            Text("No intake logged yet")
                .helmType(.body, color: HelmColor.fgMuted)
        }

        HStack(spacing: HelmSpacing.sm) {
            nutritionMacroChip("Protein", actual: snapshot.actual?.totalProteinGrams, target: snapshot.targets.proteinGrams)
            nutritionMacroChip("Carbs", actual: snapshot.actual?.totalCarbohydrateGrams, target: snapshot.targets.carbohydrateGrams)
            nutritionMacroChip("Fat", actual: snapshot.actual?.totalFatGrams, target: snapshot.targets.fatGrams)
        }

        if let gap = snapshot.targets.macroGapKilocalories,
           gap > MacroGapCalculator.significanceThresholdKcal {
            NutritionAlcoholGapRow(gapKilocalories: gap)
        }
    }

    private func nutritionMacroChip(_ label: String, actual: Double?, target: Int) -> some View {
        let actualGrams = actual.map { Int($0.rounded()) }
        return VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            if let actualGrams {
                HStack(spacing: 0) {
                    HelmNumericText(actualGrams)
                    Text("/\(target)g")
                        .helmType(.number)
                }
            } else {
                HStack(spacing: 0) {
                    HelmNumericText(target)
                    Text("g")
                        .helmType(.number)
                }
            }
            Text(label)
                .helmType(.monoTag, color: HelmColor.fgMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func estimatedBaselineSets(for summary: PrescribedSessionSummary) -> Int? {
        guard summary.readinessAdjusted else { return summary.totalSets }
        return summary.totalSets + 4
    }
}

private extension TrainingPhase {
    var label: String {
        switch self {
        case .cut: "Cut"
        case .maintain: "Maintain"
        case .gain: "Gain"
        }
    }
}

#Preview("Dashboard instrument") {
    DashboardView()
        .helmTheme()
        .environment(\.helmSkin, .instrument)
}

#Preview("Dashboard data sheet") {
    DashboardView()
        .helmTheme()
        .environment(\.helmSkin, .dataSheet)
}

#Preview("Dashboard accessibility") {
    DashboardView()
        .helmTheme()
        .dynamicTypeSize(.accessibility5)
}

#Preview("Dashboard loading") {
    ScrollView {
        HelmScreenStack {
            HelmLoadingState(rowCount: 3)
            HelmSkeletonCard(rowCount: 2)
        }
        .helmScreenPadding()
    }
    .helmTheme()
}

#Preview("Dashboard empty readiness") {
    ScrollView {
        HelmEmptyState(
            title: "Awaiting data",
            message: "Connect HealthKit to start building your readiness baseline.",
            icon: .health
        )
        .helmScreenPadding()
    }
    .helmTheme()
}

#Preview("Dashboard error") {
    ScrollView {
        HelmErrorState(
            title: "Brief unavailable",
            message: "Could not load the morning brief. Pull to refresh.",
            onRetry: {}
        )
        .helmScreenPadding()
    }
    .helmTheme()
}
