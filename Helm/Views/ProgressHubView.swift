import Core
import DesignSystem
import HealthKitIngest
import Persistence
import SwiftUI

/// Top-level Progress tab: phase + rolling volume + trends. Plan machinery lives one level deeper.
struct ProgressHubView: View {
    @Environment(\.helmSkin) private var skin
    @Bindable private var trendsController = TrendsBootstrap.controller
    @Bindable private var muscleVolumeStore = MuscleVolumeBootstrap.store
    @State private var progressionModel: ProgressionDetailModel?
    @State private var weeklyRateKg: Double?
    @State private var recompStory: RecompStory = RecompStoryClassifier.classify(RecompStorySignals())
    @State private var isShowingExercisePicker = false
    @State private var isLoadingHistory = false
    @State private var didLoadOnce = false
    @Namespace private var progressionNamespace

    private var persistence: PersistenceStore { PersistenceBootstrap.persistenceStore }

    var body: some View {
        NavigationStack {
            ScrollView {
                HelmScreenStack {
                    journeyHero
                        .helmStaggeredAppear(index: 0)
                    volumeSection
                        .helmStaggeredAppear(index: 1)
                    if !recompStory.isEmptyState {
                        RecompStoryCard(story: recompStory)
                            .helmStaggeredAppear(index: 2)
                    }
                    progressionSection
                        .helmStaggeredAppear(index: 3)
                    trendsSection
                        .helmStaggeredAppear(index: 4)
                    PatternFindingsList()
                        .helmStaggeredAppear(index: 5)
                }
                .helmScreenPadding()
            }
            .helmScreenBackground()
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.large)
            .environment(\.helmStaggerBaseDelay, HelmMotion.standard)
            .task {
                await AppTabRouter.shared.preferChromeOverContentLoad()
                guard !Task.isCancelled else { return }
                await loadIfNeeded()
            }
            .onChange(of: trendsController.snapshot) { _, _ in
                refreshRecompStory()
            }
            .refreshable {
                await reloadAll()
            }
            .sheet(isPresented: $isShowingExercisePicker) {
                ExercisePickerView(
                    fetchRecent: { (try? persistence.exercises.listRecentlyUsed(limit: 500)) ?? [] },
                    fetchExercises: { search, muscle in
                        try persistence.exercises.listForPicker(search: search, muscleGroup: muscle)
                    },
                    onSelect: { exerciseID in
                        trendsController.selectExercise(id: exerciseID)
                    }
                )
            }
        }
    }

    private var journeyHero: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                HelmSectionEyebrow("PHASE", showsArcMark: true)
                if isLoadingHistory, progressionModel == nil {
                    Text("Processing historical data…")
                        .helmType(.title, color: HelmColor.fgMuted)
                    Text("Reading plan block and recent sessions.")
                        .helmType(.body, color: HelmColor.fgMuted)
                } else {
                    Text(narrativeLine)
                        .helmType(.title)
                        .accessibilityLabel(narrativeLine)
                    if let progressionModel {
                        Text(progressionModel.blockSummary)
                            .helmType(.monoTag, color: HelmColor.fgMuted)
                    }
                }
            }
        }
        .skinAccentStripe(progressionModel?.isDeloadWeek == true ? HelmColor.ready : HelmColor.accent)
    }

    private var narrativeLine: String {
        if let progressionModel {
            return PhaseNarrativeFormatter.string(
                from: progressionModel,
                weeklyRateKg: weeklyRateKg
            )
        }
        return PhaseNarrativeFormatter.string(
            currentWeek: nil,
            mesocyclePhase: nil,
            goalPhase: nil
        )
    }

    @ViewBuilder
    private var volumeSection: some View {
        if muscleVolumeStore.isLoading, muscleVolumeStore.model == nil {
            HelmSkeletonCard(rowCount: 4)
        } else if let model = muscleVolumeStore.model {
            Card {
                MuscleVolumeBoardView(model: model, showsHeader: true)
            }
        }
    }

    private var progressionSection: some View {
        VStack(alignment: .leading, spacing: skin.sectionSpacing) {
            NavigationLink {
                ProgressionDetailContainer(matchedCardNamespace: progressionNamespace)
            } label: {
                Card {
                    HStack {
                        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                            HelmSectionEyebrow("PLAN BLOCK", showsArcMark: false)
                            Text("Mesocycle targets, load scheme, lift ladders")
                                .helmType(.body, color: HelmColor.fgSecondary)
                        }
                        Spacer()
                        HelmIconView(.chevronRight, context: .inline)
                            .foregroundStyle(HelmColor.fgMuted)
                    }
                    .helmMatchedCardDetail(id: "plan-progression", in: progressionNamespace)
                }
            }
            .buttonStyle(.helmPressableCard)
            .accessibilityLabel("Plan block. Mesocycle targets, load scheme, lift ladders")
        }
    }

    @ViewBuilder
    private var trendsSection: some View {
        VStack(alignment: .leading, spacing: skin.sectionSpacing) {
            HelmSectionEyebrow("TRENDS", showsArcMark: true)

            TrendWeightChartCard(
                rawPoints: trendsController.snapshot.bodyWeight,
                trendPoints: trendsController.snapshot.trendWeight,
                targetWeightKg: trendsController.snapshot.targetWeightKg
            )

            E1RMProgressionChartCard(
                points: trendsController.snapshot.e1RMHistory,
                exerciseName: trendsController.snapshot.selectedExerciseName,
                onPickExercise: { isShowingExercisePicker = true }
            )

            if trendsController.snapshot.canLoadMoreHistory {
                Button("Load earlier history") {
                    trendsController.loadMoreHistoryIfNeeded()
                }
                .buttonStyle(.helmSecondary)
                .frame(maxWidth: .infinity)
            }

            if let errorMessage = trendsController.errorMessage {
                HelmErrorState(
                    title: "Trends unavailable",
                    message: errorMessage,
                    onRetry: { trendsController.refresh() }
                )
            }
        }
    }

    @MainActor
    private func loadIfNeeded() async {
        if didLoadOnce {
            // Tab re-select: keep cached model; refresh volume only (cheap).
            muscleVolumeStore.refresh()
            return
        }
        await reloadAll()
        didLoadOnce = true
    }

    @MainActor
    private func reloadAll() async {
        isLoadingHistory = progressionModel == nil
        defer { isLoadingHistory = false }

        muscleVolumeStore.refresh()
        await loadProgression()
        trendsController.refresh()
        refreshRecompStory()
        Task {
            await ProactiveBootstrap.refreshPatterns()
        }
    }

    @MainActor
    private func loadProgression() async {
        do {
            let readiness = ReadinessBootstrap.readinessService.state.score
            let settings = try await PlanBootstrap.engine.loadTrainingPlan()
            weeklyRateKg = settings.phaseGoal.weeklyRateKg
            progressionModel = try await ProgressionDetailBuilder.load(
                store: PersistenceBootstrap.persistenceStore,
                engine: PlanBootstrap.engine,
                readiness: readiness
            )
        } catch {
            weeklyRateKg = nil
            progressionModel = ProgressionDetailBuilder.coldStartFallback()
        }
    }

    private func refreshRecompStory() {
        let today = HelmDay.day(for: .now, calendar: .current)
        let bodyFat = (try? persistence.bodyComposition.fetchBodyFatHistory(onOrBefore: today, limit: 8)) ?? []
        let bodyFatPercents = bodyFat
            .compactMap(\.bodyFatPercentage)
            .reversed()
        recompStory = RecompStoryBuilder.story(
            snapshot: trendsController.snapshot,
            bodyFatPercentOldestFirst: Array(bodyFatPercents)
        )
    }
}

#Preview("Progress hub") {
    ProgressHubView()
        .helmTheme()
}
