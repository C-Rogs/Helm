import Core
import DesignSystem
import SwiftUI

struct TrainView: View {
    @Bindable private var controller = TrainBootstrap.sessionController
    @Bindable private var history = TrainBootstrap.historyController
    @Bindable private var importController = TrainBootstrap.importController
    @Environment(\.scenePhase) private var scenePhase

    @State private var restRemainingSeconds: Int?
    @State private var isShowingImport = false
    @State private var didTrackInitialRestRemaining = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Group {
                    if controller.hasActiveSession, let snapshot = controller.snapshot {
                        activeSessionView(snapshot)
                    } else {
                        idleState
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if controller.numpadTarget != nil {
                    numpadOverlay
                }
            }
            .helmScreenBackground()
            .navigationTitle("Train")
            .toolbar { toolbarContent }
            .sheet(isPresented: $isShowingImport) {
                WorkoutImportView(controller: importController)
            }
            .sheet(isPresented: $controller.isShowingExercisePicker) {
                ExercisePickerView(
                    fetchExercises: controller.fetchPickerExercises(search:),
                    onSelect: { exerciseID in
                        Task { await controller.addExercise(exerciseID: exerciseID) }
                    }
                )
            }
            .confirmationDialog(
                "Finish workout?",
                isPresented: $controller.isShowingFinishConfirmation,
                titleVisibility: .visible
            ) {
                Button("Finish workout", role: .none) {
                    Task {
                        await controller.finishWorkout()
                        history.refresh()
                        history.setRecentPersonalRecords(controller.lastFinishedPersonalRecords)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This saves your logged sets.")
            }
            .confirmationDialog(
                "Discard workout?",
                isPresented: $controller.isShowingDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) {
                    Task { await controller.discardWorkout() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All progress in this session will be lost.")
            }
            .alert(
                "Workout error",
                isPresented: Binding(
                    get: { controller.errorMessage != nil },
                    set: { if !$0 { controller.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(controller.errorMessage ?? "")
            }
            .sheet(isPresented: $controller.isShowingPersonalRecords) {
                NavigationStack {
                    ScrollView {
                        PersonalRecordsCelebrationView(
                            records: controller.lastFinishedPersonalRecords,
                            exerciseName: controller.displayName(for:)
                        )
                        .padding(HelmSpacing.md)
                    }
                    .helmScreenBackground()
                    .navigationTitle("Personal records")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                controller.isShowingPersonalRecords = false
                                controller.clearFinishedPersonalRecords()
                            }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .task {
                await controller.recover()
                history.refresh()
            }
            .onChange(of: scenePhase) { _, newPhase in
                Task { await controller.handleScenePhase(newPhase) }
            }
        }
    }

    private var idleState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                VStack(spacing: HelmSpacing.lg) {
                    Text("No active session")
                        .font(HelmTypography.body)
                        .foregroundStyle(HelmColor.textSecondary)

                    Button("Start workout") {
                        Task { await controller.startWorkout() }
                    }
                    .buttonStyle(.helmPrimary)

                    Button("Import workout") {
                        isShowingImport = true
                    }
                    .buttonStyle(.helmSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, HelmSpacing.md)

                if !history.recentPersonalRecords.isEmpty {
                    PersonalRecordsCelebrationView(
                        records: history.recentPersonalRecords,
                        exerciseName: history.displayName(for:)
                    )
                }

                WorkoutTemplatesListView(history: history) { templateID in
                    Task { await controller.startWorkout(fromTemplateID: templateID) }
                }

                WorkoutHistoryListView(history: history)
            }
            .padding(HelmSpacing.md)
        }
        .onChange(of: isShowingImport) { _, isPresented in
            if !isPresented, !importController.lastImportedPersonalRecords.isEmpty {
                history.refresh()
                history.setRecentPersonalRecords(importController.lastImportedPersonalRecords)
                importController.lastImportedPersonalRecords = []
            }
        }
    }

    private func activeSessionView(_ snapshot: ActiveSessionSnapshot) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: HelmSpacing.md) {
                    if let remaining = restRemainingSeconds {
                        RestTimerBanner(remainingSeconds: remaining) {
                            Task { await controller.skipRest() }
                        }
                    }

                    if snapshot.session.exercises.isEmpty {
                        Text("Add your first exercise to begin logging sets.")
                            .helmType(.body, color: HelmColor.fgSecondary)
                            .padding(.horizontal, HelmSpacing.xs)
                    }

                    ForEach(snapshot.session.exercises) { exercise in
                        ExerciseSectionView(
                            exercise: exercise,
                            displayName: controller.displayName(for: exercise.exerciseID),
                            previousLookup: { set in
                                controller.previousFor(set: set, exerciseID: exercise.exerciseID)
                            },
                            activeField: controller.numpadTarget,
                            onOpenField: { sessionExerciseID, field, set in
                                controller.openNumpad(
                                    setID: set.id,
                                    sessionExerciseID: sessionExerciseID,
                                    field: field,
                                    currentSet: set
                                )
                            },
                            onFillPrevious: { setID in
                                Task {
                                    await controller.fillFromPrevious(
                                        setID: setID,
                                        sessionExerciseID: exercise.id
                                    )
                                }
                            },
                            onCompleteSet: { sessionExerciseID, setID in
                                Task {
                                    await controller.completeSet(
                                        sessionExerciseID: sessionExerciseID,
                                        setID: setID
                                    )
                                }
                            },
                            onRemove: {
                                Task { await controller.removeExercise(sessionExerciseID: exercise.id) }
                            }
                        )
                    }

                    Button {
                        controller.isShowingExercisePicker = true
                    } label: {
                        Label("Add exercise", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.helmSecondary)

                    Spacer(minLength: bottomContentInset)
                }
                .padding(HelmSpacing.screenGutter)
                .padding(.bottom, HelmSpacing.md)
            }

            if controller.numpadTarget == nil {
                sessionActionBar
            }
        }
        .timelineViewRestTimer(controller: controller, restRemainingSeconds: $restRemainingSeconds)
        .onChange(of: restRemainingSeconds) { _, newValue in
            guard didTrackInitialRestRemaining else {
                didTrackInitialRestRemaining = true
                controller.handleRestRemainingSecondsChange(newValue)
                return
            }
            controller.handleRestRemainingSecondsChange(newValue)
        }
        .task(id: restRemainingSeconds) {
            await controller.syncSideEffects()
        }
    }

    private var bottomContentInset: CGFloat {
        controller.numpadTarget == nil ? 88 : 300
    }

    private var sessionActionBar: some View {
        VStack(spacing: HelmSpacing.xs) {
            Divider()
                .overlay(HelmColor.hairline)
            HStack(spacing: HelmSpacing.sm) {
                Button("Discard") {
                    controller.isShowingDiscardConfirmation = true
                }
                .buttonStyle(.helmSecondary)

                Button("Finish workout") {
                    controller.isShowingFinishConfirmation = true
                }
                .buttonStyle(.helmPrimary)
            }
            .padding(.horizontal, HelmSpacing.screenGutter)
            .padding(.top, HelmSpacing.xs)
            .padding(.bottom, HelmSpacing.sm)
            .background(HelmColor.canvas)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        EmptyView()
    }

    private var numpadOverlay: some View {
        VStack(spacing: 0) {
            if !controller.numpadWorkingText.isEmpty {
                Text(controller.numpadWorkingText)
                    .helmType(.bigNumber)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, HelmSpacing.sm)
                    .background(HelmColor.surface)
            }

            HelmNumpad(
                allowsDecimal: controller.numpadTarget?.field != .reps,
                onDigit: { controller.appendNumpadDigit($0) },
                onBackspace: { controller.backspaceNumpad() },
                onNext: {
                    Task {
                        await controller.applyNumpadInput()
                        controller.numpadTarget = nil
                    }
                }
            )
            .frame(height: 300)
        }
        .background(HelmColor.canvas)
        .transition(.move(edge: .bottom))
    }
}

private struct RestTimerTimelineModifier: ViewModifier {
    let controller: TrainSessionController
    @Binding var restRemainingSeconds: Int?

    func body(content: Content) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content
                .task(id: context.date) {
                    restRemainingSeconds = await controller.remainingRestSeconds(at: context.date)
                }
        }
    }
}

private extension View {
    func timelineViewRestTimer(
        controller: TrainSessionController,
        restRemainingSeconds: Binding<Int?>
    ) -> some View {
        modifier(RestTimerTimelineModifier(controller: controller, restRemainingSeconds: restRemainingSeconds))
    }
}

#Preview("Train empty") {
    TrainView()
        .helmTheme()
}
