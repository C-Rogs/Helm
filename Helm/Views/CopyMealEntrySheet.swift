import Core
import DesignSystem
import SwiftUI

struct CopyMealEntrySheet: View {
    let sourceDay: HelmDay
    let sourceBucket: MealBucket
    let today: HelmDay
    let isSaving: Bool
    let onConfirm: (HelmDay, MealBucket) -> Void
    let onCancel: () -> Void

    @State private var targetDay: HelmDay
    @State private var targetBucket: MealBucket

    init(
        sourceDay: HelmDay,
        sourceBucket: MealBucket,
        today: HelmDay,
        isSaving: Bool,
        onConfirm: @escaping (HelmDay, MealBucket) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.sourceDay = sourceDay
        self.sourceBucket = sourceBucket
        self.today = today
        self.isSaving = isSaving
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _targetDay = State(initialValue: sourceDay)
        _targetBucket = State(initialValue: sourceBucket)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                    VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                        Text("From")
                            .helmType(.monoTag, color: HelmColor.fgMuted)
                        Text("\(sourceBucket.displayName) · \(sourceDay.formattedLabel)")
                            .helmType(.body)
                    }

                    VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                        Text("Copy to")
                            .helmType(.label)

                        HStack {
                            Button {
                                targetDay = targetDay.adding(days: -1)
                            } label: {
                                Image(systemName: "chevron.left")
                            }
                            .buttonStyle(.helmPressable)
                            .accessibilityLabel("Previous day")

                            Spacer()

                            Text(targetDay.formattedLabel)
                                .helmType(.label)

                            Spacer()

                            Button {
                                guard targetDay < today else { return }
                                targetDay = targetDay.adding(days: 1)
                            } label: {
                                Image(systemName: "chevron.right")
                            }
                            .buttonStyle(.helmPressable)
                            .disabled(targetDay >= today)
                            .accessibilityLabel("Next day")
                        }

                        if targetDay != today {
                            Button("Use today") {
                                targetDay = today
                            }
                            .buttonStyle(.helmSecondary)
                        }
                    }

                    MealBucketPicker(selection: $targetBucket)

                    Button {
                        onConfirm(targetDay, targetBucket)
                    } label: {
                        if isSaving {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Copy entry")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.helmPrimary)
                    .disabled(isSaving)
                }
                .padding(HelmSpacing.lg)
            }
            .navigationTitle("Copy entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(isSaving)
                }
            }
        }
    }
}

private extension HelmDay {
    var formattedLabel: String {
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return formatted
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }
}

#Preview {
    CopyMealEntrySheet(
        sourceDay: HelmDay(year: 2026, month: 8, day: 1),
        sourceBucket: .breakfast,
        today: HelmDay(year: 2026, month: 8, day: 2),
        isSaving: false,
        onConfirm: { _, _ in },
        onCancel: {}
    )
    .helmTheme()
}
