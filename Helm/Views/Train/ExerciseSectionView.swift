import Core
import DesignSystem
import SwiftUI

struct ExerciseSectionView: View {
    let exercise: WorkoutSessionExerciseDraft
    let displayName: String
    let targetSummary: String?
    let previousLookup: (SetEntryDraft) -> PreviousPerformance?
    let activeField: NumpadTarget?
    let onOpenField: (String, NumpadFieldKind, SetEntryDraft) -> Void
    let onFillPrevious: (String) -> Void
    let onCompleteSet: (String, String) -> Void
    let onAddSet: () -> Void
    let onRemoveSet: () -> Void
    let onRemove: () -> Void

    private var completedSetCount: Int {
        exercise.sets.filter { $0.status == .completed }.count
    }

    private var canRemoveSet: Bool {
        exercise.sets.count > max(completedSetCount, 1)
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                HStack(alignment: .top, spacing: HelmSpacing.sm) {
                    if let targetSummary {
                        PrescriptionRow(label: displayName, target: targetSummary)
                    } else {
                        Text(displayName)
                            .font(HelmTypography.headline)
                            .foregroundStyle(HelmColor.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "trash")
                            .foregroundStyle(HelmColor.destructive)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove exercise")
                }

                ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                    SetRowView(
                        setEntry: set,
                        setNumber: index + 1,
                        previous: previousLookup(set),
                        activeField: activeField,
                        sessionExerciseID: exercise.id,
                        onOpenField: { field in
                            onOpenField(exercise.id, field, set)
                        },
                        onFillPrevious: { onFillPrevious(set.id) },
                        onComplete: { onCompleteSet(exercise.id, set.id) }
                    )
                }

                HStack(spacing: HelmSpacing.sm) {
                    Button {
                        onRemoveSet()
                    } label: {
                        Label("Remove set", systemImage: "minus.circle")
                    }
                    .buttonStyle(.helmSecondary)
                    .disabled(!canRemoveSet)

                    Button {
                        onAddSet()
                    } label: {
                        Label("Add set", systemImage: "plus.circle")
                    }
                    .buttonStyle(.helmSecondary)
                }
            }
        }
    }
}

#Preview("Exercise section") {
    ExerciseSectionView(
        exercise: WorkoutSessionExerciseDraft(
            exerciseID: "bench",
            displayOrder: 0,
            exerciseMode: .weightReps,
            sets: [
                SetEntryDraft(setIndex: 0, status: .planned),
                SetEntryDraft(setIndex: 1, status: .planned, mass: Mass(kilograms: 60), reps: 10)
            ]
        ),
        displayName: "Bench Press (Barbell)",
        targetSummary: "3×8 · 80kg · RPE 8",
        previousLookup: { set in
            guard set.setIndex == 0 else { return nil }
            return PreviousPerformance(
                exerciseID: "bench",
                setIndex: 0,
                setType: .normal,
                mass: Mass(kilograms: 57.5),
                reps: 10,
                completedAt: Date()
            )
        },
        activeField: nil,
        onOpenField: { _, _, _ in },
        onFillPrevious: { _ in },
        onCompleteSet: { _, _ in },
        onAddSet: {},
        onRemoveSet: {},
        onRemove: {}
    )
    .padding()
    .helmTheme()
}
