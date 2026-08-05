import Core
import DesignSystem
import SwiftUI

extension View {
  func trainPresentationLayer(
    controller: TrainSessionController,
    history: WorkoutHistoryController,
    muscleVolumeStore: MuscleVolumeBoardStore,
    importController: WorkoutImportController,
    isShowingImport: Binding<Bool>,
    restEditorExerciseID: Binding<String?>
  ) -> some View {
    sheet(isPresented: isShowingImport) {
      WorkoutImportView(controller: importController) { plan, saveTemplate in
        await controller.startWorkout(fromImportedPlan: plan, saveTemplate: saveTemplate)
        if saveTemplate {
          history.refresh()
        }
      }
    }
    .sheet(isPresented: Binding(
      get: { controller.isShowingExercisePicker },
      set: { controller.isShowingExercisePicker = $0 }
    )) {
      ExercisePickerView(
        fetchRecent: { try controller.fetchRecentExercises() },
        fetchMuscleGroups: { try controller.fetchMuscleGroups() },
        fetchExercises: controller.fetchPickerExercises(search:muscleGroup:),
        onSelect: { exerciseID in
          Task { await controller.addExercise(exerciseID: exerciseID) }
        }
      )
    }
    .confirmationDialog(
      "Finish workout?",
      isPresented: Binding(
        get: { controller.isShowingFinishConfirmation },
        set: { controller.isShowingFinishConfirmation = $0 }
      ),
      titleVisibility: .visible
    ) {
      Button("Finish workout", role: .none) {
        Task { await controller.finishWorkout() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This saves your logged sets.")
    }
    .confirmationDialog(
      "Discard workout?",
      isPresented: Binding(
        get: { controller.isShowingDiscardConfirmation },
        set: { controller.isShowingDiscardConfirmation = $0 }
      ),
      titleVisibility: .visible
    ) {
      Button("Discard", role: .destructive) {
        Task { await controller.discardWorkout() }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("All progress in this session will be lost.")
    }
    .confirmationDialog(
      "Remove exercise?",
      isPresented: Binding(
        get: { controller.pendingDeleteExerciseID != nil },
        set: { if !$0 { controller.cancelRemoveExercise() } }
      ),
      titleVisibility: .visible,
      presenting: controller.pendingDeleteExerciseID
    ) { sessionExerciseID in
      Button("Remove exercise", role: .destructive) {
        Task { await controller.confirmRemoveExercise(presentingID: sessionExerciseID) }
      }
      Button("Cancel", role: .cancel) {
        controller.cancelRemoveExercise()
      }
    } message: { sessionExerciseID in
      Text(
        "Remove \(controller.displayName(forExerciseSessionID: sessionExerciseID))? Logged sets for this exercise will be deleted."
      )
    }
    .sheet(isPresented: Binding(
      get: { restEditorExerciseID.wrappedValue != nil },
      set: { if !$0 { restEditorExerciseID.wrappedValue = nil } }
    )) {
      if let sessionExerciseID = restEditorExerciseID.wrappedValue,
         let exercise = controller.snapshot?.session.exercises.first(where: { $0.id == sessionExerciseID }) {
        ExerciseRestEditorSheet(
          exerciseName: controller.displayName(for: exercise.exerciseID),
          currentSeconds: exercise.targetRestSeconds ?? 90
        ) { seconds in
          Task { @MainActor in
            await controller.updateExerciseRest(sessionExerciseID: sessionExerciseID, seconds: seconds)
            restEditorExerciseID.wrappedValue = nil
          }
        }
      }
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
    .sheet(isPresented: Binding(
      get: { controller.isShowingCoachPrompt },
      set: { controller.isShowingCoachPrompt = $0 }
    )) {
      InSessionCoachSheet(controller: controller)
    }
    .sheet(isPresented: Binding(
      get: { controller.isShowingManualRestTimer },
      set: { isShowing in
        controller.isShowingManualRestTimer = isShowing
        if !isShowing {
          controller.manualRestTimerOpenExpanded = false
        }
      }
    )) {
      ManualRestTimerSheet(controller: controller)
    }
    .sheet(isPresented: Binding(
      get: { controller.isShowingFinishSummary },
      set: { controller.isShowingFinishSummary = $0 }
    )) {
      TrainFinishSummarySheet(
        controller: controller,
        history: history,
        muscleVolumeStore: muscleVolumeStore
      )
    }
    .sheet(isPresented: Binding(
      get: { controller.isShowingPersonalRecords },
      set: { controller.isShowingPersonalRecords = $0 }
    )) {
      TrainPersonalRecordsSheet(controller: controller)
    }
    .sheet(isPresented: Binding(
      get: { controller.historyExerciseSessionID != nil },
      set: { if !$0 { controller.dismissExerciseHistory() } }
    )) {
      if let sessionExerciseID = controller.historyExerciseSessionID,
         let model = controller.exerciseHistoryModel(for: sessionExerciseID) {
        ExerciseHistorySheet(model: model)
      }
    }
  }
}

private struct TrainFinishSummarySheet: View {
  let controller: TrainSessionController
  let history: WorkoutHistoryController
  let muscleVolumeStore: MuscleVolumeBoardStore

  var body: some View {
    NavigationStack {
      ScrollView {
        if let summary = controller.lastFinishSummary {
          WorkoutFinishSummaryView(
            summary: summary,
            muscleLabel: TrendsChartSupport.muscleLabel
          )
        }
      }
      .helmScreenBackground()
      .navigationTitle("Session summary")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") {
            controller.dismissFinishSummary()
            controller.clearFinishSummary()
            history.refresh()
            history.setRecentPersonalRecords(controller.lastFinishedPersonalRecords)
            muscleVolumeStore.refresh()
          }
        }
      }
    }
    .presentationDetents([.large])
  }
}

private struct TrainPersonalRecordsSheet: View {
  let controller: TrainSessionController

  var body: some View {
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
}
