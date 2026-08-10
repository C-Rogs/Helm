import DesignSystem
import Persistence
import SwiftUI

/// Trend charts embedded on the Dashboard (formerly the Trends tab).
struct DashboardTrendsSection: View {
    @Environment(\.helmSkin) private var skin
    @Bindable private var controller = TrendsBootstrap.controller
    @State private var isShowingExercisePicker = false

    private var persistence: PersistenceStore { PersistenceBootstrap.persistenceStore }

    private var historyWindowBinding: Binding<TrendsHistoryWindow> {
        Binding(
            get: { controller.historyWindow },
            set: { controller.setHistoryWindow($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: skin.sectionSpacing) {
            HelmSectionEyebrow("TRENDS", showsArcMark: true)
                .padding(.top, HelmSpacing.xs)

            trendCards
        }
        .task {
            await AppTabRouter.shared.preferChromeOverContentLoad()
            guard !Task.isCancelled else { return }
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

    @ViewBuilder
    private var trendCards: some View {
        TrendWeightChartCard(
            rawPoints: controller.displayedBodyWeight,
            trendPoints: controller.displayedTrendWeight,
            targetWeightKg: controller.snapshot.targetWeightKg,
            mode: .dashboard,
            showsSparkline: false,
            showsWindowPicker: true,
            historyWindow: historyWindowBinding
        )

        E1RMProgressionChartCard(
            points: controller.displayedE1RMHistory,
            exerciseName: controller.snapshot.selectedExerciseName,
            onPickExercise: { isShowingExercisePicker = true }
        )

        if controller.historyWindow == .all, controller.snapshot.canLoadMoreHistory {
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

#Preview {
    ScrollView {
        DashboardTrendsSection()
            .helmScreenPadding()
    }
    .helmTheme()
}

#Preview("Dashboard trends data sheet") {
    ScrollView {
        DashboardTrendsSection()
            .helmScreenPadding()
    }
    .helmTheme()
    .environment(\.helmSkin, .dataSheet)
}

#Preview("Dashboard trends accessibility") {
    ScrollView {
        DashboardTrendsSection()
            .helmScreenPadding()
    }
    .helmTheme()
    .dynamicTypeSize(.accessibility5)
}
