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
        fetchRecent: { try controller.fetchRecentExercises(limit: 500) },
        fetchExercises: controller.fetchPickerExercises(search:muscleGroup:),
        onSelect: { exerciseID in
          Task { await controller.addExercise(exerciseID: exerciseID) }
        }
      )
    }
    .confirmationDialog(
      controller.sessionPrompt?.dialogTitle ?? "Confirm",
      isPresented: Binding(
        get: { controller.sessionPrompt != nil },
        set: { if !$0 { controller.dismissSessionPrompt() } }
      ),
      titleVisibility: .visible,
      presenting: controller.sessionPrompt
    ) { prompt in
      switch prompt {
      case .finish:
        Button("Finish workout") {
          controller.queueConfirmedPrompt(.finish)
        }
      case .discard:
        Button("Discard", role: .destructive) {
          controller.queueConfirmedPrompt(.discard)
        }
      case .removeExercise:
        Button("Remove exercise", role: .destructive) {
          controller.queueConfirmedPrompt(prompt)
        }
      }
      Button("Cancel", role: .cancel) {
        controller.dismissSessionPrompt()
      }
    } message: { prompt in
      switch prompt {
      case .finish:
        Text("This saves your logged sets.")
      case .discard:
        Text("All progress in this session will be lost.")
      case .removeExercise(let sessionExerciseID):
        Text(
          "Remove \(controller.displayName(forExerciseSessionID: sessionExerciseID))? Logged sets for this exercise will be deleted."
        )
      }
    }
    .onChange(of: controller.queuedConfirmedPrompt) { _, prompt in
      guard prompt != nil else { return }
      Task { @MainActor in
        await controller.performQueuedPrompt()
      }
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
        ExerciseHistorySheet(
          model: model,
          imageURL: controller.exerciseImageURL(forSessionExerciseID: sessionExerciseID)
        )
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
