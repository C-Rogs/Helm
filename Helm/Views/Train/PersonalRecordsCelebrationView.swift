import Core
import DesignSystem
import SwiftUI

struct PersonalRecordsCelebrationView: View {
    let records: [DetectedPersonalRecord]
    let exerciseName: (String) -> String

    @Environment(\.helmReduceMotion) private var reduceMotion
    @State private var settled = false
    @State private var burstActive = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                Label("New personal records", systemImage: "trophy.fill")
                    .helmType(.label, color: HelmColor.accent)

                ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                    Text(WorkoutPersonalRecordFormatter.label(for: record, exerciseName: exerciseName(record.exerciseID)))
                        .helmType(.body, color: HelmColor.fg)
                        .helmStaggeredAppear(index: index + 1)
                }
            }
            .padding(HelmSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .helmPanelChrome(.surface)

            ArcBurstView(state: .primed, isActive: burstActive)
                .frame(width: 180, height: 180)
                .offset(x: -HelmSpacing.sm, y: -HelmSpacing.lg)
        }
        .scaleEffect(settled ? 1 : 0.96)
        .opacity(settled ? 1 : 0)
        .onAppear {
            withAnimation(HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: reduceMotion)) {
                settled = true
            }
            burstActive = true
        }
    }
}

#Preview {
    PersonalRecordsCelebrationView(
        records: [
            DetectedPersonalRecord(
                exerciseID: "bench",
                metricType: .maxWeight,
                metricValue: 100
            )
        ],
        exerciseName: { _ in "Bench Press" }
    )
    .helmTheme()
    .padding()
}

#Preview("Multiple PRs") {
    PersonalRecordsCelebrationView(
        records: [
            DetectedPersonalRecord(exerciseID: "bench", metricType: .maxWeight, metricValue: 100),
            DetectedPersonalRecord(exerciseID: "squat", metricType: .bestEstimated1RM, metricValue: 180),
        ],
        exerciseName: { id in id == "bench" ? "Bench Press" : "Squat" }
    )
    .helmTheme()
    .padding()
}
