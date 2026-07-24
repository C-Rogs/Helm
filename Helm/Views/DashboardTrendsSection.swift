import DesignSystem
import Persistence
import SwiftUI

/// Trend charts embedded on the Dashboard (formerly the Trends tab).
struct DashboardTrendsSection: View {
    @Environment(\.helmSkin) private var skin
    @Bindable private var controller = TrendsBootstrap.controller
    @State private var isShowingExercisePicker = false

    private var persistence: PersistenceStore { PersistenceBootstrap.persistenceStore }

    var body: some View {
        VStack(alignment: .leading, spacing: skin.sectionSpacing) {
            Text("Trends")
                .helmType(.label)
                .padding(.top, HelmSpacing.xs)

            trendCards
        }
        .task {
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
            points: controller.snapshot.trendWeight,
            targetWeightKg: controller.snapshot.targetWeightKg,
            showsSparkline: true
        )

        ReadinessHistoryChartCard(
            points: controller.snapshot.readinessHistory
        )

        MuscleVolumeBarChartCard(
            gauges: controller.snapshot.muscleVolume
        )

        E1RMProgressionChartCard(
            points: controller.snapshot.e1RMHistory,
            exerciseName: controller.snapshot.selectedExerciseName,
            onPickExercise: { isShowingExercisePicker = true }
        )

        EnergyBalanceChartCard(
            gauges: controller.snapshot.energyBalance
        )

        if controller.snapshot.canLoadMoreHistory {
            Button("Load earlier history") {
                controller.loadMoreHistoryIfNeeded()
            }
            .buttonStyle(.helmSecondary)
            .frame(maxWidth: .infinity)
            .onAppear {
                controller.loadMoreHistoryIfNeeded()
            }
        }

        if let errorMessage = controller.errorMessage {
            Text(errorMessage)
                .helmType(.body, color: HelmColor.depleted)
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
