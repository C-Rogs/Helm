import Core
import DesignSystem
import SwiftUI

/// Card-based workout logging surface.
/// Fixed viewport: one exercise strip + one card that fills remaining height.
struct FocusCardLoggingView: View {
    let controller: TrainSessionController

    @State private var currentExerciseIndex: Int = 0
    @State private var currentSetIndex: Int = 0
    @State private var didInitialSync = false

    @Environment(\.helmReduceMotion) private var reduceMotion

    private let exerciseStripHeight: CGFloat = 40
    /// Live exercises from the controller snapshot.
    private var exercises: [WorkoutSessionExerciseDraft] {
        controller.snapshot?.session.exercises ?? []
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            exerciseStrip
                .frame(height: exerciseStripHeight)

            ScrollView {
                VStack(spacing: HelmSpacing.sm) {
                    cardArea
                }
                .padding(.horizontal, HelmSpacing.md)
                .padding(.bottom, HelmSpacing.md)
            }
        }
        .onAppear {
            syncIndicesToFirstIncomplete()
            didInitialSync = true
        }
        .task(id: neighborImagePrefetchKey) {
            prefetchNeighborImages()
        }
        .onChange(of: controller.snapshot?.session.exercises.map { $0.sets.map { "\($0.id):\($0.status.rawValue)" } }) { _, _ in
            guard didInitialSync else { return }
            guard controller.numpadTarget == nil else { return }
            reconcileIndices()
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

                    Button {
                        controller.isShowingExercisePicker = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(HelmColor.fgSecondary)
                            .frame(width: 32, height: 32)
                            .background(HelmColor.surfaceElevated, in: Capsule())
                            .contentShape(Rectangle())
                            .overlay(
                                Capsule()
                                    .stroke(HelmColor.hairline, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.helmPressable)
                    .accessibilityLabel("Add exercise")
                    .padding(.trailing, HelmSpacing.md)
                }
                .padding(.horizontal, HelmSpacing.md)
            }
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
                Text(name)
                    .helmType(isSelected ? .label : .monoTag, color: isSelected ? HelmColor.textPrimary : HelmColor.fgSecondary)
                    .lineLimit(1)

                Text("\(completed)/\(total)")
                    .helmType(.monoTag, color: isSelected ? HelmColor.accent : HelmColor.fgMuted)
                    .padding(.horizontal, HelmSpacing.xxs)
                    .padding(.vertical, 1)
                    .background(
                        isSelected
                            ? HelmColor.accent.opacity(0.12)
                            : HelmColor.surfaceElevated,
                        in: Capsule()
                    )
            }
            .padding(.horizontal, HelmSpacing.sm)
            .padding(.vertical, 6)
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
                VStack(spacing: HelmSpacing.sm) {
                    FocusExerciseCard(
                        exercise: currentExercise,
                        displayName: controller.displayName(for: currentExercise.exerciseID),
                        coachingCue: controller.coachingCue(for: currentExercise.exerciseID),
                        imageURL: exerciseImageURL(for: currentExercise.exerciseID),
                        imageMaxHeight: HelmLayout.exerciseHistoryImageHeight,
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
                                let didComplete = await controller.completeSet(
                                    sessionExerciseID: currentExercise.id,
                                    setID: set.id
                                )
                                if didComplete {
                                    advanceToNextSet()
                                }
                            }
                        }
                    )
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

                    completedSetsStack(currentExercise)

                    if currentExercise.sets.contains(where: { $0.setType.countsAsPrescribedWorkingSet }) {
                        setManagementControls(currentExercise)
                    }

                    if currentExerciseIndex == exercises.count - 1 {
                        TrainSessionActionBar(
                            isFinishing: controller.isFinishingWorkout,
                            onDiscard: { controller.requestDiscardConfirmation() },
                            onFinish: { controller.requestFinishConfirmation() }
                        )
                    }
                }
                .transition(.opacity)
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

    // MARK: - Completed sets stack

    private func completedSetsStack(_ exercise: WorkoutSessionExerciseDraft) -> some View {
        let completed = exercise.sets
            .filter { $0.status == .completed }
            .sorted { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
        let completedIDs = completed.map(\.id)

        return Group {
            if !completed.isEmpty {
                VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                    Text("Completed")
                        .helmType(.monoTag, color: HelmColor.fgMuted)

                    ForEach(completed) { set in
                        completedSetRow(set, exercise: exercise)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(
                    HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: reduceMotion),
                    value: completedIDs
                )
            }
        }
    }

    private func completedSetRow(_ set: SetEntryDraft, exercise: WorkoutSessionExerciseDraft) -> some View {
        HStack(spacing: HelmSpacing.xs) {
            Text(setTypeGlyph(for: set))
                .helmType(.monoTag, color: setTypeColor(for: set))
                .frame(width: 20, alignment: .leading)

            Text(completedSetValue(for: set))
                .helmType(.monoTag, color: HelmColor.fgSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()

            Button(action: {
                Task { @MainActor in
                    await controller.completeSet(
                        sessionExerciseID: exercise.id,
                        setID: set.id
                    )
                }
            }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.caption)
                    .foregroundStyle(HelmColor.fgMuted)
                    .frame(width: HelmLayout.minTapTarget, height: HelmLayout.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.helmPressable)
            .accessibilityLabel("Undo set")
        }
        .padding(.horizontal, HelmSpacing.sm)
        .padding(.vertical, HelmSpacing.xs)
        .background(HelmColor.surfaceElevated.opacity(0.55), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: HelmRadius.sm)
                .strokeBorder(HelmColor.hairline, lineWidth: 1)
        }
    }

    private func setTypeGlyph(for set: SetEntryDraft) -> String {
        set.setType.loggerGlyph(setNumber: set.setIndex + 1)
    }

    private func setTypeColor(for set: SetEntryDraft) -> Color {
        switch set.setType {
        case .warmup: HelmColor.fgSecondary
        case .dropSet: HelmColor.accent
        case .failure: HelmColor.destructive
        default: HelmColor.fgMuted
        }
    }

    private func completedSetValue(for set: SetEntryDraft) -> String {
        let weight = set.mass.map { formatWeight($0.kilograms) } ?? "-"
        let reps = set.reps.map(String.init) ?? "-"
        let rpe = set.rpe.map { formattedRPE($0) } ?? "-"
        return "\(weight)kg × \(reps) @ \(rpe)"
    }

    private func formattedRPE(_ rpe: Double) -> String {
        rpe.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", rpe)
            : String(format: "%.1f", rpe)
    }

    private func formatWeight(_ kilograms: Double) -> String {
        kilograms.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", kilograms)
            : String(format: "%.1f", kilograms)
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

    // MARK: - Set management

    private func setManagementControls(_ exercise: WorkoutSessionExerciseDraft) -> some View {
        let workingCount = exercise.sets.filter { $0.setType.countsAsPrescribedWorkingSet }.count
        let completedWorkingCount = exercise.sets.filter {
            $0.setType.countsAsPrescribedWorkingSet && $0.status == .completed
        }.count
        let canRemove = workingCount > max(completedWorkingCount, 1)

        return HStack(spacing: HelmSpacing.sm) {
            Button {
                Task { @MainActor in await controller.removeSet(sessionExerciseID: exercise.id) }
            } label: {
                Label("Remove set", systemImage: "minus.circle")
            }
            .buttonStyle(.helmSecondary)
            .disabled(!canRemove)

            Button {
                Task { @MainActor in await controller.addSet(sessionExerciseID: exercise.id) }
            } label: {
                Label("Add set", systemImage: "plus.circle")
            }
            .buttonStyle(.helmSecondary)
        }
        .font(.caption)
    }

    // MARK: - Helpers

    private func syncIndicesToFirstIncomplete() {
        guard !exercises.isEmpty else { return }
        currentExerciseIndex = min(currentExerciseIndex, exercises.count - 1)

        for (exIdx, exercise) in exercises.enumerated() {
            if let setIdx = firstIncompleteSetIndex(for: exercise) {
                if exIdx != currentExerciseIndex || setIdx != currentSetIndex {
                    currentExerciseIndex = exIdx
                    currentSetIndex = setIdx
                }
                return
            }
        }
        currentExerciseIndex = max(0, exercises.count - 1)
        if let lastEx = exercises.last {
            currentSetIndex = max(0, lastEx.sets.count - 1)
        }
    }

    /// Keeps the card pointing at a real set without yanking the user off their
    /// current exercise: clamp indices first; jump to next incomplete only when
    /// the current exercise is fully done or the pointed-at set disappeared.
    private func reconcileIndices() {
        guard !exercises.isEmpty else { return }

        guard exercises.indices.contains(currentExerciseIndex) else {
            syncIndicesToFirstIncomplete()
            return
        }

        let exercise = exercises[currentExerciseIndex]

        if !exercise.sets.indices.contains(currentSetIndex) {
            // Set was removed: prefer the first incomplete in this exercise.
            if let setIdx = firstIncompleteSetIndex(for: exercise) {
                currentSetIndex = setIdx
            } else if exercise.sets.isEmpty {
                syncIndicesToFirstIncomplete()
            } else {
                currentSetIndex = max(0, exercise.sets.count - 1)
            }
            return
        }

        if exercise.sets[currentSetIndex].status == .completed,
           let setIdx = firstIncompleteSetIndex(for: exercise),
           setIdx != currentSetIndex {
            currentSetIndex = setIdx
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

        for idx in (currentSetIndex + 1)..<currentExercise.sets.count {
            if currentExercise.sets[idx].status != .completed {
                withAnimation(HelmMotion.standardAnimation) {
                    currentSetIndex = idx
                }
                return
            }
        }

        for exIdx in (currentExerciseIndex + 1)..<exercises.count {
            if let setIdx = firstIncompleteSetIndex(for: exercises[exIdx]) {
                withAnimation(HelmMotion.standardAnimation) {
                    currentExerciseIndex = exIdx
                    currentSetIndex = setIdx
                }
                return
            }
        }

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
        controller.exerciseImageURL(for: exerciseID)
    }

    private func prefetchNeighborImages() {
        for offset in [-1, 0, 1] {
            let index = currentExerciseIndex + offset
            guard let exercise = exercises[safe: index],
                  let url = exerciseImageURL(for: exercise.exerciseID) else { continue }
            ExerciseImagePrefetcher.prefetch(url)
        }
    }

    private var neighborImagePrefetchKey: String {
        let neighborIDs = [currentExerciseIndex - 1, currentExerciseIndex, currentExerciseIndex + 1]
            .compactMap { exercises[safe: $0]?.exerciseID }
        let urls = neighborIDs.compactMap { exerciseImageURL(for: $0)?.absoluteString }
        return "\(currentExerciseIndex)|\(urls.joined(separator: ","))"
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
        controller: TrainBootstrap.sessionController
    )
    .padding()
    .helmTheme()
}
