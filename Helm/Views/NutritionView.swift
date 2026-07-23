import DesignSystem
import HealthKitIngest
import SwiftUI

struct NutritionView: View {
    private var nutritionService: NutritionService { NutritionBootstrap.nutritionService }
    private var prescriptionService: PrescriptionService { PlanBootstrap.prescriptionService }
    @Bindable private var chatController = ChatBootstrap.controller

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                    switch nutritionService.state {
                    case .loading:
                        loadingCard
                    case let .ready(snapshot):
                        NutritionDaySummaryCard(snapshot: snapshot, showTrend: true)
                            .explainable(
                                ExplainableMetricMappers.nutrition(
                                    snapshot,
                                    coachAvailable: chatController.isCoachAvailable
                                ),
                                onAskCoach: chatController.requestCoachHandoff(prompt:)
                            )
                    }
                }
                .padding(HelmSpacing.md)
            }
            .helmScreenBackground()
            .navigationTitle("Nutrition")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await nutritionService.refresh(
                    prescriptionSummary: prescriptionService.state.summary
                )
            }
            .onChange(of: prescriptionService.state) { _, newState in
                Task {
                    await nutritionService.refresh(prescriptionSummary: newState.summary)
                }
            }
        }
    }

    private var loadingCard: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                Text("Nutrition")
                    .helmType(.label)
                Text("Loading today's intake…")
                    .helmType(.body, color: HelmColor.fgMuted)
            }
        }
    }
}

#Preview {
    NutritionView()
        .helmTheme()
}
