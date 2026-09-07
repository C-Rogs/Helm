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
    @State private var usualMealStore = UsualMealStore()
    @State private var contributorDetailsVisible = true
    @State private var sleepSummary: SleepNightSummary?
    @State private var showSettings = false
    @State private var todayStepCount: Int?
    @AppStorage(StepGoalPreferences.isEnabledKey) private var stepGoalEnabled = false
    @AppStorage(StepGoalPreferences.goalCountKey) private var stepGoalCount =
        StepGoalPreferences.defaultGoalCount
    @State private var moreBodyExpanded = true
    @State private var phaseNarrative: String?
    @State private var recompStory: RecompStory?
    @State private var isShowingReadinessExplain = false
    @Bindable private var tabRouter = AppTabRouter.shared
    @Bindable private var trendsController = TrendsBootstrap.controller
    @Namespace private var readinessNamespace
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
                    heroCard
                        .helmStaggeredAppear(index: 1)
                    thresholdInsightCard
                        .helmStaggeredAppear(index: 2)
                    // Always-visible body context (Signal wedge). Not buried in a closed disclosure.
                    readinessCard
                        .helmStaggeredAppear(index: 3)
                    sleepCard
                        .helmStaggeredAppear(index: 4)
                    if heroKind != .brief {
                        briefCard
                            .helmStaggeredAppear(index: 5)
                    }
                    if heroKind != .nutrition {
                        nutritionTargetsCard
                            .helmStaggeredAppear(index: 6)
                    }
                    if let recompStory {
                        RecompStoryCard(story: recompStory)
                            .helmStaggeredAppear(index: 7)
                    }
                    progressionTeaserCard
                        .helmStaggeredAppear(index: 8)
                    DashboardPatternTeaser()
                        .helmStaggeredAppear(index: 9)
                    moreBodySection
                        .helmStaggeredAppear(index: 10)

                    Button {
                        chatController.requestCoachHandoff(prompt: "What should I focus on today?")
                    } label: {
                        Label("Ask Coach", helmIcon: .chat, context: .inline)
                    }
                    .buttonStyle(.helmSecondary)
                    .helmStaggeredAppear(index: 11)
                }
                .helmScreenPadding()
            }
            .helmScreenBackground()
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: HelmIcon.settings.rawValue)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $isShowingReadinessExplain) {
                if case let .scored(score) = readinessService.state {
                    ExplainSheet(
                        metric: ExplainableMetricMappers.readiness(
                            score,
                            coachAvailable: chatController.isCoachAvailable
                        ),
                        onAskCoach: chatController.requestCoachHandoff(prompt:)
                    )
                }
            }
            .onChange(of: tabRouter.pendingOpenSettings) { _, pending in
                guard pending else { return }
                showSettings = true
                tabRouter.consumePendingOpenSettings()
            }
            .environment(\.helmStaggerBaseDelay, HelmMotion.standard)
            .task {
                await AppTabRouter.shared.preferChromeOverContentLoad()
                guard !Task.isCancelled else { return }
                await readinessService.refresh()
                await loadSleepSummary()
                await prescriptionService.refresh(readiness: readinessService.state.score)
                await nutritionService.refresh(
                    prescriptionSummary: prescriptionService.state.summary
                )
                if case let .ready(snapshot) = nutritionService.state {
                    usualMealStore.reload(for: snapshot.helmDay)
                }
                await briefService.refresh(
                    readiness: readinessService.state.score,
                    prescriptionSummary: prescriptionService.state.summary
                )
                await ProactiveBootstrap.refreshThresholdInsights()
                await ProactiveBootstrap.refreshPatterns()
                muscleVolumeStore.refresh()
                loadTodaySteps()
                await loadPhaseNarrative()
                trendsController.refresh()
                refreshRecompStory()
            }
            .onChange(of: trendsController.snapshot) { _, _ in
                refreshRecompStory()
            }
            .task {
                for await _ in HealthKitBootstrap.healthKitIngest.updates(for: .activity) {
                    loadTodaySteps()
                }
            }
            .task {
                for await snapshot in HealthKitBootstrap.healthKitIngest.updates(for: .sleep) {
                    guard snapshot.status.lastSyncSampleCount > 0
                        || snapshot.status.lastSyncDeletedCount > 0
                    else { continue }
                    await loadSleepSummary()
                }
            }
            .onChange(of: readinessService.state) { _, newState in
                Task {
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
            .onChange(of: nutritionService.state) { _, newState in
                if case let .ready(snapshot) = newState {
                    usualMealStore.reload(for: snapshot.helmDay)
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
        let store = PersistenceBootstrap.persistenceStore
        let summary = await Task.detached(priority: .userInitiated) {
            try? store.sleep.nightSummary(forWakeCalendarDay: wakeDay)
        }.value
        sleepSummary = summary
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
                MuscleVolumeBoardContainer(matchedCardNamespace: muscleVolumeNamespace)
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
        case let .restDay(rest):
            Button {
                AppTabRouter.shared.openTrain()
            } label: {
                prescriptionShell(subtitle: rest.title, showsChevron: true) {
                    Text(rest.summary)
                        .helmType(.body, color: HelmColor.fgSecondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(.helmPressableCard)
        case let .prescribed(summary):
            TodaySessionTeaser(
                title: summary.title,
                totalSets: summary.totalSets,
                phaseLabel: summary.phase.label,
                readinessAdjusted: summary.readinessAdjusted,
                onOpenTrain: { AppTabRouter.shared.openTrain() }
            )
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

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text(greetingText)
                .helmType(.title)
            Text(heroActionSubtitle)
                .helmType(.body, color: HelmColor.fgSecondary)
            if let phaseNarrative {
                Text(phaseNarrative)
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                    .accessibilityLabel(phaseNarrative)
            }
            if let todayStepCount {
                // Observe AppStorage so Settings toggles refresh this readout.
                let _ = (stepGoalEnabled, stepGoalCount)
                Text(StepGoalPreferences.greetingStepsLine(stepCount: todayStepCount))
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                    .accessibilityLabel(
                        StepGoalPreferences.greetingStepsAccessibilityLabel(
                            stepCount: todayStepCount
                        )
                    )
            }
        }
    }

    private enum DashboardHeroKind {
        case session
        case nutrition
        case brief
    }

    private var heroKind: DashboardHeroKind {
        switch prescriptionService.state {
        case .prescribed, .restDay, .awaitingCatalog:
            return .session
        case .loading:
            if case .ready = nutritionService.state {
                return .nutrition
            }
            return .brief
        }
    }

    private var heroActionSubtitle: String {
        switch heroKind {
        case .session:
            if case .restDay = prescriptionService.state {
                return "Rest day. Recover, then check Train."
            }
            return "One thing: start today's session."
        case .nutrition:
            return "One thing: log your next meal."
        case .brief:
            return "Today's plan from your body."
        }
    }

    @ViewBuilder
    private var heroCard: some View {
        switch heroKind {
        case .session:
            prescriptionCard
        case .nutrition:
            nutritionTargetsCard
        case .brief:
            briefCard
        }
    }

    private var progressionTeaserCard: some View {
        Button {
            AppTabRouter.shared.openProgress()
        } label: {
            Card {
                HStack {
                    VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                        HelmSectionEyebrow("PROGRESSION", showsArcMark: false)
                        Text("Open Progress for phase, trends, and patterns")
                            .helmType(.body, color: HelmColor.fgSecondary)
                        if let phaseNarrative {
                            Text(phaseNarrative)
                                .helmType(.monoTag, color: HelmColor.fgMuted)
                        }
                    }
                    Spacer()
                    HelmIconView(.chevronRight, context: .inline)
                        .foregroundStyle(HelmColor.fgMuted)
                }
            }
        }
        .buttonStyle(.helmPressableCard)
        .accessibilityLabel(
            phaseNarrative.map { "Progression. \($0)" }
                ?? "Progression. Open Progress tab"
        )
    }

    @ViewBuilder
    private var moreBodySection: some View {
        DisclosureGroup(isExpanded: $moreBodyExpanded) {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                muscleVolumeSummaryCard
                progressShortcutCard
            }
            .padding(.top, HelmSpacing.sm)
        } label: {
            Text("Volume & progress")
                .helmType(.label)
        }
        .tint(HelmColor.accent)
    }

    private var progressShortcutCard: some View {
        Button {
            AppTabRouter.shared.openProgress()
        } label: {
            Card {
                HStack {
                    VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                        HelmSectionEyebrow("TRENDS & PATTERNS", showsArcMark: true)
                        Text("Weight trend, e1RM, and associations live on Progress")
                            .helmType(.body, color: HelmColor.fgSecondary)
                    }
                    Spacer()
                    HelmIconView(.trends, context: .inline)
                        .foregroundStyle(HelmColor.fgMuted)
                    HelmIconView(.chevronRight, context: .inline)
                        .foregroundStyle(HelmColor.fgMuted)
                }
            }
        }
        .buttonStyle(.helmPressableCard)
        .accessibilityLabel("Trends and patterns. Open Progress tab")
    }

    private func loadTodaySteps() {
        let day = HelmDay.day(for: .now, calendar: .current)
        todayStepCount = try? PersistenceBootstrap.persistenceStore.dailyMetrics.fetch(helmDay: day)?.stepCount
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
            readinessShell(subtitle: "") {
                HelmEmptyState(
                    title: "Waiting on Health",
                    message: "Connect Apple Health so ARC can read HRV, resting HR, and sleep.",
                    icon: .health,
                    actionTitle: "Open Settings"
                ) {
                    showSettings = true
                }
            }
        case let .buildingBaseline(_, message):
            readinessShell(subtitle: "") {
                HelmEmptyState(
                    title: "Building baseline",
                    message: message,
                    icon: .health
                )
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
                state: helmState,
                onExplain: {
                    isShowingReadinessExplain = true
                }
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

    @ViewBuilder
    private func readinessShell<Content: View>(
        subtitle: String,
        state: HelmState? = nil,
        onExplain: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let card = Card {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                HStack(spacing: HelmSpacing.xs) {
                    HelmSectionEyebrow("ARC")
                    Spacer(minLength: HelmSpacing.sm)
                    if let onExplain {
                        HelmExplainInfoButton(
                            accessibilityLabel: "Show how ARC is calculated",
                            action: onExplain
                        )
                    }
                    if let state {
                        stateBadge(for: state)
                    }
                }

                content()

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .helmType(.body, color: HelmColor.fgMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
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
            Card {
                VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                    Button {
                        AppTabRouter.shared.openNutrition()
                    } label: {
                        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                            HStack {
                                HelmSectionEyebrow("NUTRITION", showsArcMark: false)
                                Spacer()
                                HelmIconView(.chevronRight, context: .inline)
                                    .foregroundStyle(HelmColor.fgMuted)
                            }
                            compactNutritionContent(snapshot: snapshot)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.helmPressableCard)

                    if let proposal = usualMealStore.nextDashboardProposal {
                        UsualMealConfirmRow(
                            proposal: proposal,
                            isLogging: usualMealStore.loggingBucket == proposal.bucket,
                            showsSomethingElse: true,
                            onYes: {
                                Task {
                                    await usualMealStore.log(proposal, helmDay: snapshot.helmDay)
                                }
                            },
                            onSomethingElse: {
                                AppTabRouter.shared.openNutrition(
                                    focus: NutritionNavigationFocus(
                                        helmDay: snapshot.helmDay,
                                        bucket: proposal.bucket,
                                        startSearch: true
                                    )
                                )
                            }
                        )
                    } else {
                        HStack(spacing: HelmSpacing.sm) {
                            Button {
                                AppTabRouter.shared.openNutrition()
                            } label: {
                                Label("Log food", helmIcon: .plus, context: .inline)
                            }
                            .buttonStyle(.helmSecondary)

                            if NutritionPreferencesStore.shared.isCheckInDue(today: snapshot.helmDay) {
                                Button {
                                    AppTabRouter.shared.openNutrition(
                                        focus: NutritionNavigationFocus(
                                            helmDay: snapshot.helmDay,
                                            openWeeklyCheckIn: true
                                        )
                                    )
                                } label: {
                                    Text("Review week")
                                }
                                .buttonStyle(.helmSecondary)
                            }
                        }
                    }
                }
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
            if snapshot.eatToKcal > 0 {
                HelmNumericText(abs(snapshot.remainingKcal))
                    .helmType(.bigNumber)
                Text(snapshot.remainingKcal < 0 ? "kcal over" : "kcal left")
                    .helmType(.body, color: HelmColor.fgMuted)
            } else {
                Text("Pending")
                    .helmType(.bigNumber, color: HelmColor.fgMuted)
                Text("eat-to pending")
                    .helmType(.body, color: HelmColor.fgMuted)
            }
            Spacer()
            if let demand = snapshot.budgetDay?.demand {
                Text(demand.displayLabel)
                    .helmType(.monoTag, color: HelmColor.fgMuted)
            } else {
                Text(snapshot.dayType.rawValue.capitalized)
                    .helmType(.monoTag, color: HelmColor.fgMuted)
            }
        }

        if snapshot.eatToKcal > 0 {
            HStack(spacing: HelmSpacing.xxs) {
                HelmNumericText(snapshot.loggedKcal ?? 0)
                Text("of")
                    .helmType(.body, color: HelmColor.fgSecondary)
                HelmNumericText(snapshot.eatToKcal)
                Text("kcal eat-to")
                    .helmType(.body, color: HelmColor.fgSecondary)
            }
        } else if snapshot.loggedKcal != nil {
            HStack(spacing: HelmSpacing.xxs) {
                HelmNumericText(snapshot.loggedKcal ?? 0)
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

    @MainActor
    private func loadPhaseNarrative() async {
        do {
            let readiness = readinessService.state.score
            let settings = try await PlanBootstrap.engine.loadTrainingPlan()
            let model = try await ProgressionDetailBuilder.load(
                store: PersistenceBootstrap.persistenceStore,
                engine: PlanBootstrap.engine,
                readiness: readiness
            )
            phaseNarrative = PhaseNarrativeFormatter.string(
                from: model,
                weeklyRateKg: settings.phaseGoal.weeklyRateKg
            )
        } catch {
            phaseNarrative = nil
        }
    }

    private func refreshRecompStory() {
        let store = PersistenceBootstrap.persistenceStore
        let bodyFat = (try? store.bodyComposition.fetchBodyFatHistory(onOrBefore: today, limit: 8)) ?? []
        let bodyFatPercents = bodyFat.compactMap(\.bodyFatPercentage).reversed()
        let story = RecompStoryBuilder.story(
            snapshot: trendsController.snapshot,
            bodyFatPercentOldestFirst: Array(bodyFatPercents)
        )
        // Keep warm empty off Dashboard; Progress hub always shows the card.
        recompStory = story.isEmptyState ? nil : story
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
            title: "Waiting on Health",
            message: "Connect Apple Health so ARC can read HRV, resting HR, and sleep.",
            icon: .health,
            actionTitle: "Open Settings"
        ) {}
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
