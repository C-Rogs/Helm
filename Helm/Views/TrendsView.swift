import DesignSystem
import Persistence
import SwiftUI

struct TrendsView: View {
    @Environment(\.helmSkin) private var skin
    @Bindable private var controller = TrendsBootstrap.controller
    @State private var isShowingExercisePicker = false

    private var persistence: PersistenceStore { PersistenceBootstrap.persistenceStore }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: skin.sectionSpacing) {
                    trendCards
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
                    fetchRecent: { (try? persistence.exercises.listRecentlyUsed()) ?? [] },
                    fetchMuscleGroups: { (try? persistence.exercises.listMuscleGroups()) ?? [] },
                    fetchExercises: { search, muscle in
                        try persistence.exercises.listForPicker(search: search, muscleGroup: muscle)
                    },
                    onSelect: { exerciseID in
                        controller.selectExercise(id: exerciseID)
                    }
                )
            }
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
