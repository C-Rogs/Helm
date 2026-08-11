import Core
import DesignSystem
import SwiftUI

/// Bottom sheet showing all completed sets across all exercises.
/// Each completed set is tappable to undo. Current set is shown as pending.
struct FocusSessionLogSheet: View {
    let exercises: [WorkoutSessionExerciseDraft]
    let displayName: (String) -> String
    let onUndoSet: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HelmSpacing.md) {
                    ForEach(exercises) { exercise in
                        exerciseSection(exercise)
                    }
                }
                .padding(HelmSpacing.md)
            }
            .helmScreenBackground()
            .navigationTitle("Session Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .buttonStyle(.helmPrimary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Exercise section

    private func exerciseSection(_ exercise: WorkoutSessionExerciseDraft) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            let completed = exercise.sets.filter { $0.status == .completed }.count
            let total = exercise.sets.count

            HStack {
                Text(displayName(exercise.exerciseID))
                    .helmType(.label)
                Spacer()
                Text("\(completed)/\(total)")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
            }

            Card {
                VStack(spacing: 0) {
                    ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                        setRow(set, exerciseID: exercise.id, setNumber: index + 1)
                        if index < exercise.sets.count - 1 {
                            Divider()
                                .overlay(HelmColor.hairline)
                                .padding(.leading, HelmSpacing.lg)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Set row

    private func setRow(_ set: SetEntryDraft, exerciseID: String, setNumber: Int) -> some View {
        let isCompleted = set.status == .completed

        return Button {
            if isCompleted {
                onUndoSet(exerciseID, set.id)
            }
        } label: {
            HStack(spacing: HelmSpacing.sm) {
                // Status icon
                ZStack {
                    Circle()
                        .fill(isCompleted ? HelmColor.accent : Color.clear)
                        .frame(width: 24, height: 24)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    isCompleted ? HelmColor.accent : HelmColor.hairline,
                                    lineWidth: 1.5
                                )
                        }

                    if isCompleted {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(HelmColor.buttonPrimaryForeground)
                    }
                }

                // Set number
                Text("Set \(setNumber)")
                    .helmType(.body, color: isCompleted ? HelmColor.textPrimary : HelmColor.fgMuted)
                    .frame(width: 48, alignment: .leading)

                // Set type
                if let abbreviation = set.setType.loggerAbbreviation {
                    Text(abbreviation)
                        .helmType(.monoTag, color: HelmColor.fgSecondary)
                        .padding(.horizontal, HelmSpacing.xxs)
                        .padding(.vertical, 1)
                        .background(HelmColor.surfaceElevated, in: Capsule())
                }

                Spacer()

                // Performance
                if isCompleted {
                    Text(performanceLabel(for: set))
                        .helmType(.monoTag, color: HelmColor.fgSecondary)
                } else {
                    Text("--")
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                }

                // Undo hint
                if isCompleted {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption)
                        .foregroundStyle(HelmColor.fgMuted)
                        .padding(.leading, HelmSpacing.xxs)
                }
            }
            .padding(.vertical, HelmSpacing.sm)
            .padding(.horizontal, HelmSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: set, setNumber: setNumber))
        .accessibilityHint(isCompleted ? "Tap to undo this set" : "")
    }

    // MARK: - Helpers

    private func performanceLabel(for set: SetEntryDraft) -> String {
        var parts: [String] = []

        if let mass = set.mass {
            let kg = mass.kilograms
            parts.append(kg.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0fkg", kg)
                : String(format: "%.1fkg", kg))
        }

        if let reps = set.reps {
            parts.append("× \(reps)")
        }

        if let rpe = set.rpe {
            parts.append(" RPE \(String(format: "%.0f", rpe))")
        }

        return parts.isEmpty ? "--" : parts.joined()
    }

    private func accessibilityLabel(for set: SetEntryDraft, setNumber: Int) -> String {
        let status = set.status == .completed ? "Completed" : "Pending"
        let perf = performanceLabel(for: set)
        return "Set \(setNumber), \(status), \(perf)"
    }
}

#Preview("Session log sheet") {
    FocusSessionLogSheet(
        exercises: [
            WorkoutSessionExerciseDraft(
                exerciseID: "bench",
                displayOrder: 0,
                exerciseMode: .weightReps,
                sets: [
                    SetEntryDraft(setIndex: 0, status: .completed, mass: Mass(kilograms: 80), reps: 8, rpe: 7),
                    SetEntryDraft(setIndex: 1, status: .completed, mass: Mass(kilograms: 82.5), reps: 8, rpe: 8),
                    SetEntryDraft(setIndex: 2, status: .planned),
                ]
            ),
            WorkoutSessionExerciseDraft(
                exerciseID: "squat",
                displayOrder: 1,
                exerciseMode: .weightReps,
                sets: [
                    SetEntryDraft(setIndex: 0, status: .completed, mass: Mass(kilograms: 100), reps: 5, rpe: 8),
                    SetEntryDraft(setIndex: 1, status: .planned),
                ]
            ),
        ],
        displayName: { id in
            ["bench": "Bench Press (Barbell)", "squat": "Squat (Barbell)"][id] ?? id
        },
        onUndoSet: { exerciseID, setID in
            print("Undo set \(setID) from \(exerciseID)")
        }
    )
    .helmTheme()
}