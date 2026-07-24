import Core
import DesignSystem
import SwiftUI

struct PersonalRecordsCelebrationView: View {
    let records: [DetectedPersonalRecord]
    let exerciseName: (String) -> String

    @Environment(\.helmReduceMotion) private var reduceMotion
    @State private var settled = false

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Label("New personal records", systemImage: "trophy.fill")
                .font(HelmTypography.headline)
                .foregroundStyle(HelmColor.accent)

            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                Text(WorkoutPersonalRecordFormatter.label(for: record, exerciseName: exerciseName(record.exerciseID)))
                    .font(HelmTypography.callout)
                    .foregroundStyle(HelmColor.textPrimary)
                    .helmStaggeredAppear(index: index + 1)
            }
        }
        .padding(HelmSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HelmColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: HelmRadius.md))
        .scaleEffect(settled ? 1 : 0.96)
        .opacity(settled ? 1 : 0)
        .onAppear {
            withAnimation(HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: reduceMotion)) {
                settled = true
            }
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
