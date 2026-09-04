import DesignSystem
import HealthKitIngest
import Persistence
import SwiftUI

struct PatternFindingsView: View {
    var body: some View {
        ScrollView {
            PatternFindingsList()
                .helmScreenPadding()
        }
        .helmScreenBackground()
        .navigationTitle("Patterns")
        .navigationBarTitleDisplayMode(.large)
    }
}

struct PatternFindingsList: View {
    @Environment(\.helmSkin) private var skin
    @State private var patternCards: [PatternFindingCardModel] = []

    private var persistence: PersistenceStore { PersistenceBootstrap.persistenceStore }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: skin.sectionSpacing) {
            HelmSectionEyebrow("PATTERNS", showsArcMark: true)
            if patternCards.isEmpty {
                HelmEmptyState(
                    title: "Need more days",
                    message: "Associations ship once both arms have at least 12 days. Log sleep, drinks, and training as usual.",
                    icon: .empty
                )
            } else {
                ForEach(patternCards) { card in
                    PatternFindingCard(
                        model: card,
                        onConfirmToMemory: card.canConfirmToMemory
                            ? { confirmPattern(id: card.id) }
                            : nil
                    )
                }
            }
        }
        .task {
            await ProactiveBootstrap.refreshPatterns()
            reloadPatterns()
        }
        .refreshable { reloadPatterns() }
    }

    private func reloadPatterns() {
        let service = PatternEvaluationService(store: persistence)
        patternCards = (try? service.cardModels()) ?? []
    }

    private func confirmPattern(id: String) {
        let service = PatternEvaluationService(store: persistence)
        try? service.confirmToMemory(id: id)
        reloadPatterns()
    }
}

struct TrendsView: View {
    @Environment(\.helmSkin) private var skin
    @Bindable private var controller = TrendsBootstrap.controller
    @State private var isShowingExercisePicker = false

    private var persistence: PersistenceStore { PersistenceBootstrap.persistenceStore }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: skin.sectionSpacing) {
                trendCards
                PatternFindingsList()
            }
            .helmScreenPadding()
        }
        .helmScreenBackground()
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.large)
        .task {
            controller.refresh()
        }
        .refreshable {
            controller.refresh()
        }
        .sheet(isPresented: $isShowingExercisePicker) {
            ExercisePickerView(
                fetchRecent: { (try? persistence.exercises.listRecentlyUsed(limit: 500)) ?? [] },
                fetchExercises: { search, muscle in
                    try persistence.exercises.listForPicker(search: search, muscleGroup: muscle)
                },
                onSelect: { exerciseID in
                    controller.selectExercise(id: exerciseID)
                }
            )
        }
    }

    @ViewBuilder
    private var trendCards: some View {
        TrendWeightChartCard(
            rawPoints: controller.snapshot.bodyWeight,
            trendPoints: controller.snapshot.trendWeight,
            targetWeightKg: controller.snapshot.targetWeightKg
        )

        E1RMProgressionChartCard(
            points: controller.snapshot.e1RMHistory,
            exerciseName: controller.snapshot.selectedExerciseName,
            onPickExercise: { isShowingExercisePicker = true }
        )

        if controller.snapshot.canLoadMoreHistory {
            Button("Load earlier history") {
                controller.loadMoreHistoryIfNeeded()
            }
            .buttonStyle(.helmSecondary)
            .frame(maxWidth: .infinity)
        }

        if let errorMessage = controller.errorMessage {
            HelmErrorState(
                title: "Trends unavailable",
                message: errorMessage,
                onRetry: { controller.refresh() }
            )
        }
    }
}

#Preview("Trends loading") {
    ScrollView {
        HelmScreenStack {
            HelmLoadingState(rowCount: 4)
        }
        .helmScreenPadding()
    }
    .helmTheme()
}

#Preview("Trends error") {
    ScrollView {
        HelmErrorState(
            title: "Trends unavailable",
            message: "Could not read workout history.",
            onRetry: {}
        )
        .helmScreenPadding()
    }
    .helmTheme()
}

#Preview("Trends empty charts") {
    ScrollView {
        LazyVStack(spacing: HelmSpacing.lg) {
            TrendWeightChartCard(rawPoints: [], trendPoints: [], targetWeightKg: nil)
            E1RMProgressionChartCard(
                points: [],
                exerciseName: "Squat (Barbell)",
                onPickExercise: {}
            )
        }
        .helmScreenPadding()
    }
    .helmTheme()
}

#Preview("Trends accessibility") {
    TrendsView()
        .helmTheme()
        .dynamicTypeSize(.accessibility5)
}

#Preview("Trends fixture cards instrument") {
    ScrollView {
        LazyVStack(spacing: HelmSpacing.lg) {
            TrendWeightChartCard(
                rawPoints: TrendChartFixtures.bodyWeight,
                trendPoints: TrendChartFixtures.trendWeight,
                targetWeightKg: TrendChartFixtures.targetWeightKg
            )
            E1RMProgressionChartCard(
                points: TrendChartFixtures.e1RMHistory,
                exerciseName: "Squat (Barbell)",
                onPickExercise: {}
            )
        }
        .padding(HelmSpacing.md)
    }
    .helmTheme()
    .environment(\.helmSkin, .instrument)
}

#Preview("Trends fixture cards data sheet") {
    ScrollView {
        LazyVStack(spacing: HelmSpacing.sm) {
            TrendWeightChartCard(
                rawPoints: TrendChartFixtures.bodyWeight,
                trendPoints: TrendChartFixtures.trendWeight,
                targetWeightKg: TrendChartFixtures.targetWeightKg
            )
            E1RMProgressionChartCard(
                points: TrendChartFixtures.e1RMHistory,
                exerciseName: "Squat (Barbell)",
                onPickExercise: {}
            )
        }
        .padding(HelmSpacing.md)
    }
    .helmTheme()
    .environment(\.helmSkin, .dataSheet)
}
