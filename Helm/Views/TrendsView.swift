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
                .padding(HelmSpacing.md)
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
            points: controller.snapshot.trendWeight,
            targetWeightKg: controller.snapshot.targetWeightKg
        )

        ReadinessHistoryChartCard(
            points: controller.snapshot.readinessHistory
        )

        MuscleVolumeArcGridCard(
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

#Preview("Trends") {
    TrendsView()
        .helmTheme()
}

#Preview("Trends fixture cards instrument") {
    ScrollView {
        LazyVStack(spacing: HelmSpacing.lg) {
            TrendWeightChartCard(
                points: TrendChartFixtures.trendWeight,
                targetWeightKg: TrendChartFixtures.targetWeightKg
            )
            ReadinessHistoryChartCard(points: TrendChartFixtures.readinessHistory)
            MuscleVolumeArcGridCard(gauges: TrendChartFixtures.muscleVolume)
            E1RMProgressionChartCard(
                points: TrendChartFixtures.e1RMHistory,
                exerciseName: "Squat (Barbell)",
                onPickExercise: {}
            )
            EnergyBalanceChartCard(gauges: TrendChartFixtures.energyBalance)
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
                points: TrendChartFixtures.trendWeight,
                targetWeightKg: TrendChartFixtures.targetWeightKg
            )
            ReadinessHistoryChartCard(points: TrendChartFixtures.readinessHistory)
            MuscleVolumeArcGridCard(gauges: TrendChartFixtures.muscleVolume)
            E1RMProgressionChartCard(
                points: TrendChartFixtures.e1RMHistory,
                exerciseName: "Squat (Barbell)",
                onPickExercise: {}
            )
            EnergyBalanceChartCard(gauges: TrendChartFixtures.energyBalance)
        }
        .padding(HelmSpacing.md)
    }
    .helmTheme()
    .environment(\.helmSkin, .dataSheet)
}
