import Core
import DesignSystem
import SwiftUI

/// Card-based workout logging surface.
/// Replaces the vertical table of ExerciseSectionView cards with a single focused card
/// showing one exercise and one set at a time, plus a compact exercise strip and session log.
struct FocusCardLoggingView: View {
    let exercises: [WorkoutSessionExerciseDraft]
    let controller: TrainSessionController

    /// Bound to the parent's sheet state so the session log can be presented.
    @Binding var isShowingSessionLog: Bool

    @State private var currentExerciseIndex: Int = 0
    @State private var currentSetIndex: Int = 0

    @Environment(\.helmReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            exerciseStrip
            cardArea
            sessionLogButton
            Spacer(minLength: 0)
        }
        .onAppear {
            syncIndicesToFirstIncomplete()
        }
        .onChange(of: exercises.map(\.sets.count)) { _, _ in
            // Re-sync when exercises change (add/remove sets from controller)
            syncIndicesToFirstIncomplete()
        }
        .onChange(of: controller.snapshot?.session.exercises.map { $0.id }) { _, _ in
            syncIndicesToFirstIncomplete()
        }
    }

    // MARK: - Exercise strip

    private var exerciseStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HelmSpacing.xs) {
                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                    exercisePill(exercise, index: index)
                }
            }
            .padding(.horizontal, HelmSpacing.md)
        }
        .padding(.vertical, HelmSpacing.sm)
    }

    private func exercisePill(_ exercise: WorkoutSessionExerciseDraft, index: Int) -> some View {
        let isSelected = index == currentExerciseIndex
        let name = controller.displayName(for: exercise.exerciseID)
        let completed = exercise.sets.filter { $0.status == .completed }.count
        let total = exercise.sets.count

        return Button {
            withAnimation(HelmMotion.standardAnimation) {
                currentExerciseIndex = index
                currentSetIndex = firstIncompleteSetIndex(for: exercise) ?? 0
            }
        } label: {
            HStack(spacing: HelmSpacing.xxs) {
                if isSelected {
                    Text(name)
                        .helmType(.label, color: HelmColor.textPrimary)
                        .lineLimit(1)
                } else {
                    Text(name)
                        .helmType(.monoTag, color: HelmColor.fgSecondary)
                        .lineLimit(1)
                }

                Text("\(completed)/\(total)")
                    .helmType(.monoTag, color: isSelected ? HelmColor.accent : HelmColor.fgMuted)
                    .padding(.horizontal, HelmSpacing.xxs)
                    .padding(.vertical, 2)
                    .background(
                        isSelected
                            ? HelmColor.accent.opacity(0.12)
                            : HelmColor.surfaceElevated,
                        in: Capsule()
                    )
            }
            .padding(.horizontal, HelmSpacing.sm)
            .padding(.vertical, HelmSpacing.xs)
            .background(
                isSelected
                    ? HelmColor.accent.opacity(0.06)
                    : HelmColor.surfaceElevated,
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? HelmColor.accent : HelmColor.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.helmPressable)
        .accessibilityLabel("\(name), \(completed) of \(total) sets completed")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Card area

    private var cardArea: some View {
        Group {
            if let currentExercise = exercises[safe: currentExerciseIndex] {
                FocusExerciseCard(
                    exercise: currentExercise,
                    displayName: controller.displayName(for: currentExercise.exerciseID),
                    coachingCue: controller.coachingCue(for: currentExercise.exerciseID),
                    imageURL: exerciseImageURL(for: currentExercise.exerciseID),
                    currentSetIndex: currentSetIndex,
                    previous: controller.previousFor(
                        set: currentExercise.sets[safe: currentSetIndex] ?? SetEntryDraft(setIndex: currentSetIndex),
                        exerciseID: currentExercise.exerciseID
                    ),
                    activeField: controller.numpadTarget,
                    numpadSelectAll: controller.numpadSelectAll,
                    fieldDisplayText: { set, field in
                        controller.displayText(for: field, set: set, exerciseID: currentExercise.exerciseID)
                    },
                    onOpenField: { field in
                        Task {
                            guard let set = currentExercise.sets[safe: currentSetIndex] else { return }
                            await controller.openNumpad(
                                setID: set.id,
                                sessionExerciseID: currentExercise.id,
                                field: field,
                                currentSet: set
                            )
                        }
                    },
                    onFillPrevious: {
                        Task {
                            guard let set = currentExercise.sets[safe: currentSetIndex] else { return }
                            await controller.fillFromPrevious(
                                setID: set.id,
                                sessionExerciseID: currentExercise.id
                            )
                        }
                    },
                    onCycleSetType: {
                        Task { @MainActor in
                            guard let set = currentExercise.sets[safe: currentSetIndex] else { return }
                            await controller.cycleSetType(setID: set.id)
                        }
                    },
                    onCompleteSet: {
                        Task { @MainActor in
                            guard let set = currentExercise.sets[safe: currentSetIndex] else { return }
                            await controller.completeSet(
                                sessionExerciseID: currentExercise.id,
                                setID: set.id
                            )
                            // After completing, advance to next incomplete set
                            advanceToNextSet()
                        }
                    }
                )
                .padding(.horizontal, HelmSpacing.md)
                .transition(.opacity)
                .id("exercise-\(currentExercise.id)-set-\(currentSetIndex)")
            }
        }
        .animation(
            HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: reduceMotion),
            value: currentExerciseIndex
        )
        .animation(
            HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: reduceMotion),
            value: currentSetIndex
        )
    }

    // MARK: - Session log button

    private var sessionLogButton: some View {
        let allCompleted = exercises.flatMap(\.sets).filter { $0.status == .completed }.count
        let allTotal = exercises.flatMap(\.sets).count

        return Button {
            isShowingSessionLog = true
        } label: {
            HStack(spacing: HelmSpacing.xs) {
                Image(systemName: "list.clipboard")
                    .font(.caption)
                Text("Session Log")
                    .helmType(.label)
                Text("\(allCompleted)/\(allTotal) completed")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.caption)
                    .foregroundStyle(HelmColor.fgMuted)
            }
            .padding(.horizontal, HelmSpacing.md)
            .padding(.vertical, HelmSpacing.sm)
            .background(HelmColor.surfaceElevated, in: RoundedRectangle(cornerRadius: HelmRadius.md))
        }
        .buttonStyle(.helmPressable)
        .padding(.horizontal, HelmSpacing.md)
        .padding(.top, HelmSpacing.xs)
        .accessibilityLabel("Session log, \(allCompleted) of \(allTotal) sets completed")
    }

    // MARK: - Helpers

    private func syncIndicesToFirstIncomplete() {
        guard !exercises.isEmpty else { return }

        for (exIdx, exercise) in exercises.enumerated() {
            if let setIdx = firstIncompleteSetIndex(for: exercise) {
                if exIdx != currentExerciseIndex || setIdx != currentSetIndex {
                    currentExerciseIndex = exIdx
                    currentSetIndex = setIdx
                }
                return
            }
        }
        // All sets complete: stay on last exercise, last set
        currentExerciseIndex = max(0, exercises.count - 1)
        if let lastEx = exercises.last {
            currentSetIndex = max(0, lastEx.sets.count - 1)
        }
    }

    private func firstIncompleteSetIndex(for exercise: WorkoutSessionExerciseDraft) -> Int? {
        for (idx, set) in exercise.sets.enumerated() {
            if set.status != .completed {
                return idx
            }
        }
        return nil
    }

    private func advanceToNextSet() {
        guard let currentExercise = exercises[safe: currentExerciseIndex] else { return }

        // First try next set in same exercise
        for idx in (currentSetIndex + 1)..<currentExercise.sets.count {
            if currentExercise.sets[idx].status != .completed {
                withAnimation(HelmMotion.standardAnimation) {
                    currentSetIndex = idx
                }
                return
            }
        }

        // Then try next exercise
        for exIdx in (currentExerciseIndex + 1)..<exercises.count {
            if let setIdx = firstIncompleteSetIndex(for: exercises[exIdx]) {
                withAnimation(HelmMotion.standardAnimation) {
                    currentExerciseIndex = exIdx
                    currentSetIndex = setIdx
                }
                return
            }
        }

        // All done: stay on last set of current exercise
        currentSetIndex = max(0, currentExercise.sets.count - 1)
    }

    private func exerciseImageURL(for exerciseID: String) -> URL? {
        guard let summary = controller.exerciseSummaries[exerciseID],
              let gifURL = summary.gifURL else { return nil }
        return URL(string: gifURL)
    }
}

// MARK: - Safe array subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview("Focus card logging") {
    FocusCardLoggingView(
        exercises: [
            WorkoutSessionExerciseDraft(
                exerciseID: "bench",
                displayOrder: 0,
                exerciseMode: .weightReps,
                targetRestSeconds: 90,
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
                targetRestSeconds: 120,
                sets: [
                    SetEntryDraft(setIndex: 0, status: .completed, mass: Mass(kilograms: 100), reps: 5, rpe: 8),
                    SetEntryDraft(setIndex: 1, status: .planned),
                ]
            ),
        ],
        controller: TrainBootstrap.sessionController,
        isShowingSessionLog: .constant(false)
    )
    .padding()
    .helmTheme()
}