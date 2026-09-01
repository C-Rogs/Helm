import Core
import DesignSystem
import HealthKitIngest
import SwiftUI

struct TodaysSessionPreviewSheet: View {
    let summary: PrescribedSessionSummary
    var onStart: () -> Void
    var onDiscuss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                    VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                        Text(summary.title)
                            .helmType(.title)
                        Text(summary.summary)
                            .helmType(.body, color: HelmColor.fgSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if summary.readinessAdjusted {
                        Text("Volume trimmed for readiness")
                            .helmType(.monoTag, color: HelmColor.depleted)
                    }

                    Card {
                        VStack(spacing: 0) {
                            ForEach(summary.exercises) { exercise in
                                HelmRuledRow {
                                    PrescriptionRow(
                                        label: exercise.displayName,
                                        target: prescriptionTargetText(for: exercise)
                                    )
                                }
                            }
                        }
                    }

                    if !summary.rationale.isEmpty {
                        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                            ForEach(summary.rationale, id: \.self) { line in
                                Text(line)
                                    .helmType(.body, color: HelmColor.fgMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    Button("Start today's session") {
                        onStart()
                    }
                    .buttonStyle(.helmPrimary)
                }
                .helmScreenPadding()
                .padding(.bottom, HelmLayout.trainScrollBottomInset)
            }
            .helmScreenBackground()
            .navigationTitle("Today's session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Discuss") {
                        onDiscuss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func prescriptionTargetText(for exercise: PrescribedExerciseSummary) -> String {
        var parts = ["\(exercise.targetSets)×\(exercise.targetRepRange)"]
        if let load = exercise.targetLoad {
            parts.append(load)
        }
        if let rpe = exercise.targetRPE {
            parts.append(rpe)
        }
        return parts.joined(separator: " · ")
    }
}

#Preview("Today's session preview") {
    TodaysSessionPreviewSheet(
        summary: PrescribedSessionSummary(
            phase: .maintain,
            emphasis: nil,
            title: "Pull",
            summary: "Back + Biceps · 16 sets · week 3 accumulating",
            rationale: ["Back: 8/14 hard sets this week."],
            exercises: [
                PrescribedExerciseSummary(
                    id: "row",
                    displayName: "Bent Over Row (Barbell)",
                    targetSets: 4,
                    targetRepRange: "8-10",
                    targetLoad: "80kg",
                    targetRPE: "RPE 8"
                ),
                PrescribedExerciseSummary(
                    id: "pulldown",
                    displayName: "Lat Pulldown (Cable)",
                    targetSets: 3,
                    targetRepRange: "10-12",
                    targetLoad: nil,
                    targetRPE: "RPE 8"
                )
            ],
            totalSets: 7,
            readinessAdjusted: true
        ),
        onStart: {},
        onDiscuss: {}
    )
    .helmTheme()
}
