import Core
import DesignSystem
import SwiftUI

struct ExerciseSectionView: View {
    let exercise: WorkoutSessionExerciseDraft
    let displayName: String
    let targetSummary: String?
    let coachingCue: String?
    let restSeconds: Int
    let isReorderMode: Bool
    let previousLookup: (SetEntryDraft) -> PreviousPerformance?
    let activeField: NumpadTarget?
    let numpadSelectAll: Bool
    let validationMessage: String?
    let advisoryMessage: (String) -> String?
    let shakeToken: Int
    let fieldDisplayText: (SetEntryDraft, NumpadFieldKind) -> String
    let badgeText: (String) -> String?
    let encouragementGlyph: (String) -> EncouragementGlyph?
    let showsPRCelebration: (String) -> Bool
    let onOpenField: (String, NumpadFieldKind, SetEntryDraft) -> Void
    let onFillPrevious: (String) -> Void
    let onCycleSetType: (String) -> Void
    let onCompleteSet: (String, String) -> Void
    let onAddSet: () -> Void
    let onRemoveSet: () -> Void
    let onRemove: () -> Void
    let onEnterReorderMode: () -> Void
    let onEditRest: () -> Void
    let onOpenHistory: () -> Void
    let onDropExercise: (String) -> Void

    @Environment(\.helmReduceMotion) private var reduceMotion

    private var completedSetCount: Int {
        exercise.sets.filter { $0.status == .completed }.count
    }

    private var setIdentity: [String] {
        exercise.sets.map(\.id)
    }

    private var canRemoveSet: Bool {
        exercise.sets.count > max(completedSetCount, 1)
    }

    var body: some View {
        Group {
            if isReorderMode {
                cardContent
                    .draggable(exercise.id) {
                        Text(displayName)
                            .padding(HelmSpacing.sm)
                            .background(HelmColor.surfaceElevated, in: RoundedRectangle(cornerRadius: HelmRadius.sm))
                    }
                    .dropDestination(for: String.self) { items, _ in
                        guard let sourceID = items.first else { return false }
                        onDropExercise(sourceID)
                        return true
                    }
            } else {
                cardContent
                    .contextMenu {
                        Button("Reorder exercises") {
                            onEnterReorderMode()
                        }
                    }
            }
        }
    }

    private var cardContent: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                HStack(alignment: .top, spacing: HelmSpacing.sm) {
                    if isReorderMode {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(HelmColor.fgMuted)
                            .padding(.top, HelmSpacing.xxs)
                    }

                    VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                        Button(action: onOpenHistory) {
                            Group {
                                if let targetSummary {
                                    PrescriptionRow(label: displayName, target: targetSummary)
                                } else {
                                    Text(displayName)
                                        .helmFont(.label)
                                        .foregroundStyle(HelmColor.textPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .buttonStyle(.helmPressable)
                        .disabled(isReorderMode)
                        .accessibilityLabel("View history for \(displayName)")

                        Button {
                            onEditRest()
                        } label: {
                            Text("Rest \(restSeconds)s")
                                .helmType(.monoTag, color: HelmColor.fgSecondary)
                        }
                        .buttonStyle(.helmPressable)
                        .disabled(isReorderMode)

                        if let coachingCue {
                            Text(coachingCue)
                                .helmType(.body, color: HelmColor.fgSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if !isReorderMode {
                        Button(role: .destructive, action: onRemove) {
                            HelmIconView(.trash, context: .inline)
                                .foregroundStyle(HelmColor.destructive)
                        }
                        .buttonStyle(.helmPressable)
                        .accessibilityLabel("Remove exercise")
                    }
                }

                if !isReorderMode {
                    ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                        SetRowView(
                            setEntry: set,
                            setNumber: index + 1,
                            previous: previousLookup(set),
                            activeField: activeField,
                            numpadSelectAll: numpadSelectAll,
                            validationMessage: validationMessage,
                            advisoryMessage: advisoryMessage(set.id),
                            shakeToken: shakeToken,
                            badgeText: badgeText(set.id),
                            encouragementGlyph: encouragementGlyph(set.id),
                            showsPRCelebration: showsPRCelebration(set.id),
                            fieldDisplayText: fieldDisplayText,
                            sessionExerciseID: exercise.id,
                            onOpenField: { field in
                                onOpenField(exercise.id, field, set)
                            },
                            onFillPrevious: { onFillPrevious(set.id) },
                            onCycleSetType: { onCycleSetType(set.id) },
                            onComplete: { onCompleteSet(exercise.id, set.id) }
                        )
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .bottom)),
                                removal: .opacity.combined(with: .move(edge: .top))
                            )
                        )
                    }
                    .animation(
                        HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: reduceMotion),
                        value: setIdentity
                    )

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
}

#Preview("Exercise section") {
    ExerciseSectionView(
        exercise: WorkoutSessionExerciseDraft(
            exerciseID: "bench",
            displayOrder: 0,
            exerciseMode: .weightReps,
            targetRestSeconds: 90,
            sets: [
                SetEntryDraft(setIndex: 0, status: .planned),
                SetEntryDraft(setIndex: 1, status: .planned, mass: Mass(kilograms: 60), reps: 10)
            ]
        ),
        displayName: "Bench Press (Barbell)",
        targetSummary: "3×8 · 80kg · RPE 8",
        coachingCue: "Drive through your heels and keep your chest proud.",
        restSeconds: 90,
        isReorderMode: false,
        previousLookup: { _ in nil },
        activeField: nil,
        numpadSelectAll: false,
        validationMessage: nil,
        advisoryMessage: { _ in nil },
        shakeToken: 0,
        fieldDisplayText: { set, field in
            switch field {
            case .weight: set.mass.map { String(format: "%.0f", $0.kilograms) } ?? ""
            case .reps: set.reps.map(String.init) ?? ""
            case .rpe: set.rpe.map { String(format: "%.0f", $0) } ?? ""
            }
        },
        badgeText: { _ in nil },
        encouragementGlyph: { _ in nil },
        showsPRCelebration: { _ in false },
        onOpenField: { _, _, _ in },
        onFillPrevious: { _ in },
        onCycleSetType: { _ in },
        onCompleteSet: { _, _ in },
        onAddSet: {},
        onRemoveSet: {},
        onRemove: {},
        onEnterReorderMode: {},
        onEditRest: {},
        onOpenHistory: {},
        onDropExercise: { _ in }
    )
    .padding()
    .helmTheme()
}
