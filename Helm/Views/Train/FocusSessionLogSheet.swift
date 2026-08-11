import Core
import DesignSystem
import SwiftUI

/// Bottom sheet showing all sets across all exercises.
/// Each completed set is tappable to undo. Planned sets are shown as pending.
struct FocusSessionLogSheet: View {
    let displayName: (String) -> String
    let onUndoSet: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Live exercises from the controller snapshot.
    private var exercises: [WorkoutSessionExerciseDraft] {
        TrainBootstrap.sessionController.exercisesForDisplay()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HelmSpacing.md) {
                    if exercises.isEmpty {
                        emptyState
                    } else {
                        ForEach(exercises) { exercise in
                            exerciseSection(exercise)
                        }
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

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: HelmSpacing.md) {
            Spacer(minLength: 60)
            Image(systemName: "list.clipboard")
                .font(.largeTitle)
                .foregroundStyle(HelmColor.fgMuted)
            Text("No sets logged yet")
                .helmType(.body, color: HelmColor.fgSecondary)
            Text("Log a set in the card view to see it here.")
                .helmType(.monoTag, color: HelmColor.fgMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
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
                dismiss()
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
        displayName: { id in
            ["bench": "Bench Press (Barbell)", "squat": "Squat (Barbell)"][id] ?? id
        },
        onUndoSet: { exerciseID, setID in
            print("Undo set \(setID) from \(exerciseID)")
        }
    )
    .helmTheme()
}