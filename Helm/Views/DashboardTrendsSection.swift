import DesignSystem
import HealthKitIngest
import Persistence
import SwiftUI

/// Trend charts embedded on the Dashboard (formerly the Trends tab).
struct DashboardTrendsSection: View {
    @Environment(\.helmSkin) private var skin
    @Bindable private var controller = TrendsBootstrap.controller
    @State private var isShowingExercisePicker = false
    @State private var patternTeaser: String?

    private var persistence: PersistenceStore { PersistenceBootstrap.persistenceStore }

    private var historyWindowBinding: Binding<TrendsHistoryWindow> {
        Binding(
            get: { controller.historyWindow },
            set: { controller.setHistoryWindow($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: skin.sectionSpacing) {
            NavigationLink {
                TrendsView()
            } label: {
                HStack {
                    HelmSectionEyebrow("TRENDS", showsArcMark: true)
                    Spacer()
                    Text("ALL")
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                    HelmIconView(.chevronRight, context: .inline)
                        .foregroundStyle(HelmColor.fgMuted)
                }
                .padding(.top, HelmSpacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Trends and patterns")

            trendCards
            patternsLink
        }
        .task {
            await AppTabRouter.shared.preferChromeOverContentLoad()
            guard !Task.isCancelled else { return }
            await ProactiveBootstrap.refreshPatterns()
            controller.refresh()
            reloadPatternTeaser()
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

    private var patternsLink: some View {
        NavigationLink {
            PatternFindingsView()
        } label: {
            Card {
                VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                    HStack {
                        HelmSectionEyebrow("PATTERNS")
                        Spacer()
                        HelmIconView(.chevronRight, context: .inline)
                            .foregroundStyle(HelmColor.fgMuted)
                    }
                    if let patternTeaser {
                        Text(patternTeaser)
                            .helmType(.label)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text("Need more days. Associations ship once both arms have at least 12 days.")
                            .helmType(.body, color: HelmColor.fgSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
        }
        .buttonStyle(.helmPressableCard)
        .accessibilityLabel(patternTeaser.map { "Patterns. \($0)" } ?? "Patterns. Need more days")
    }

    private func reloadPatternTeaser() {
        let cards = (try? PatternEvaluationService(store: persistence).cardModels()) ?? []
        patternTeaser = cards.first?.headline
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
