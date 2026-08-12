import Core
import DesignSystem
import SwiftUI

/// Card-based workout logging surface.
/// Shows one exercise and one set at a time in a focused card,
/// with a compact exercise strip and session log sheet.
struct FocusCardLoggingView: View {
    let controller: TrainSessionController

    @Binding var isShowingSessionLog: Bool

    @State private var currentExerciseIndex: Int = 0
    @State private var currentSetIndex: Int = 0
    @State private var didInitialSync = false

    @Environment(\.helmReduceMotion) private var reduceMotion

    /// Live exercises from the controller snapshot.
    private var exercises: [WorkoutSessionExerciseDraft] {
        controller.snapshot?.session.exercises ?? []
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            exerciseStrip
            cardArea
            sessionLogButton
            sessionFooter
            Spacer(minLength: 0)
        }
        .onAppear {
            syncIndicesToFirstIncomplete()
            didInitialSync = true
        }
        .onChange(of: controller.snapshot?.session.exercises.map(\.sets.count)) { _, _ in
            guard didInitialSync else { return }
            // Skip sync when numpad is active (user is typing)
            guard controller.numpadTarget == nil else { return }
            syncIndicesToFirstIncomplete()
        }
    }

    // MARK: - Exercise strip

    private var exerciseStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HelmSpacing.xs) {
                    ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                        exercisePill(exercise, index: index)
                            .id("pill-\(exercise.id)")
                    }
                }
                .padding(.horizontal, HelmSpacing.md)
            }
            .padding(.vertical, HelmSpacing.sm)
            .onChange(of: currentExerciseIndex) { _, _ in
                guard let ex = exercises[safe: currentExerciseIndex] else { return }
                withAnimation {
                    proxy.scrollTo("pill-\(ex.id)", anchor: .center)
                }
            }
        }
    }

    private func exercisePill(_ exercise: WorkoutSessionExerciseDraft, index: Int) -> some View {
        let isSelected = index == currentExerciseIndex
        let name = controller.displayName(for: exercise.exerciseID)
        let completed = exercise.sets.filter { $0.status == .completed }.count
        let total = exercise.sets.count

        return Button {
            guard !exercises.isEmpty else { return }
            let clamped = min(index, exercises.count - 1)
            withAnimation(HelmMotion.standardAnimation) {
                currentExerciseIndex = clamped
                currentSetIndex = firstIncompleteSetIndex(for: exercises[clamped]) ?? 0
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
        VStack(spacing: 0) {
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
                    showsPRCelebration: currentExercise.sets[safe: currentSetIndex].map { controller.showsPRCelebration(forSetID: $0.id) } ?? false,
                    encouragementGlyph: currentExercise.sets[safe: currentSetIndex].flatMap { controller.encouragementGlyph(forSetID: $0.id) },
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
                            advanceToNextSet()
                        }
                    }
                )
                .padding(.horizontal, HelmSpacing.md)
                .transition(.opacity)
                .id("exercise-\(currentExercise.id)-set-\(currentSetIndex)")
                .gesture(
                    DragGesture(minimumDistance: 50)
                        .onEnded { value in
                            if value.translation.width < -60 {
                                navigateToNextExercise()
                            } else if value.translation.width > 60 {
                                navigateToPreviousExercise()
                            }
                        }
                )
            } else {
                emptyExercisesView
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

    private var emptyExercisesView: some View {
        VStack(spacing: HelmSpacing.md) {
            Spacer()
            Text("Add your first exercise to begin logging sets.")
                .helmType(.body, color: HelmColor.fgSecondary)
            Button {
                controller.isShowingExercisePicker = true
            } label: {
                Label("Add exercise", helmIcon: .plus, context: .inline)
            }
            .buttonStyle(.helmSecondary)
            Spacer()
        }
    }

    // MARK: - Session log button

    private var sessionLogButton: some View {
        let allCompleted = exercises.flatMap(\.sets).filter { $0.status == .completed }.count
        let allTotal = exercises.flatMap(\.sets).count

        return Button {
            isShowingSessionLog = true
        } label: {
            HStack(spacing: HelmSpacing.xs) {
                Image(systemName: "checklist")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(HelmColor.fgSecondary)

                Text("Session Log")
                    .helmType(.label, color: HelmColor.textPrimary)

                Spacer()

                Text("\(allCompleted) of \(allTotal)")
                    .helmType(.monoTag, color: HelmColor.fgMuted)

                Image(systemName: "chevron.up")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(HelmColor.fgMuted)
            }
            .padding(.horizontal, HelmSpacing.md)
            .padding(.vertical, HelmSpacing.sm)
            .background(HelmColor.surfaceElevated)
            .overlay(alignment: .top) {
                Divider().overlay(HelmColor.hairline)
            }
        }
        .buttonStyle(.plain)
        .padding(.top, HelmSpacing.xs)
        .accessibilityLabel("Session log, \(allCompleted) of \(allTotal) sets completed")
    }

    // MARK: - Session footer

    private var sessionFooter: some View {
        HStack(spacing: HelmSpacing.sm) {
            Button {
                controller.isShowingExercisePicker = true
            } label: {
                Label("Add", helmIcon: .plus, context: .inline)
            }
            .buttonStyle(.helmSecondary)

            Spacer()

            Button {
                controller.isShowingDiscardConfirmation = true
            } label: {
                Text("Discard")
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .buttonStyle(.helmSecondary)
            .disabled(controller.isFinishingWorkout)

            HelmActionButton(
                "Finish",
                phase: controller.isFinishingWorkout ? .loading : .idle,
                successTitle: "Done"
            ) {
                controller.isShowingFinishConfirmation = true
            }
        }
        .padding(.horizontal, HelmSpacing.md)
        .padding(.top, HelmSpacing.sm)
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

    private func navigateToNextExercise() {
        guard currentExerciseIndex + 1 < exercises.count else { return }
        let nextIdx = currentExerciseIndex + 1
        withAnimation(HelmMotion.standardAnimation) {
            currentExerciseIndex = nextIdx
            currentSetIndex = firstIncompleteSetIndex(for: exercises[nextIdx]) ?? 0
        }
    }

    private func navigateToPreviousExercise() {
        guard currentExerciseIndex > 0 else { return }
        let prevIdx = currentExerciseIndex - 1
        withAnimation(HelmMotion.standardAnimation) {
            currentExerciseIndex = prevIdx
            currentSetIndex = firstIncompleteSetIndex(for: exercises[prevIdx]) ?? 0
        }
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
        controller: TrainBootstrap.sessionController,
        isShowingSessionLog: .constant(false)
    )
    .padding()
    .helmTheme()
}