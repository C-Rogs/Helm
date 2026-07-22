import Core
import DesignSystem
import SwiftUI

struct PersonalRecordsCelebrationView: View {
    let records: [DetectedPersonalRecord]
    let exerciseName: (String) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Label("New personal records", systemImage: "trophy.fill")
                .font(HelmTypography.headline)
                .foregroundStyle(HelmColor.accent)

            ForEach(records) { record in
                Text(WorkoutPersonalRecordFormatter.label(for: record, exerciseName: exerciseName(record.exerciseID)))
                    .font(HelmTypography.callout)
                    .foregroundStyle(HelmColor.textPrimary)
            }
        }
        .padding(HelmSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HelmColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: HelmRadius.md))
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
