import DesignSystem
import Persistence
import SwiftUI

struct WorkoutImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var controller: WorkoutImportController
    let onStartWorkout: (ImportedWorkoutPlan, Bool) async -> Void

    @State private var isShowingFormatGuide = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                Text("Paste a workout plan from Gemini or another coach. Helm pre-fills exercises, sets, and targets so you can log the session in the gym.")
                    .helmFont(.body)
                    .foregroundStyle(HelmColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    isShowingFormatGuide.toggle()
                } label: {
                    HStack(spacing: HelmSpacing.xs) {
                        Text("Supported formats")
                            .helmFont(.label)
                        Spacer(minLength: 0)
                        Image(systemName: isShowingFormatGuide ? "chevron.up" : "chevron.down")
                            .helmFont(.label)
                    }
                    .foregroundStyle(HelmColor.textSecondary)
                }
                .buttonStyle(.plain)

                if isShowingFormatGuide {
                    formatGuide
                }

                TextEditor(text: $controller.pasteText)
                    .helmFont(.number)
                    .frame(minHeight: 220)
                    .padding(HelmSpacing.sm)
                    .background(HelmColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: HelmRadius.md))

                if let errorMessage = controller.errorMessage {
                    Text(errorMessage)
                        .helmFont(.body)
                        .foregroundStyle(HelmColor.destructive)
                }

                Spacer(minLength: 0)

                Button("Preview workout") {
                    controller.parseForPreview()
                }
                .buttonStyle(.helmPrimary)
                .disabled(controller.pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(HelmSpacing.md)
            .helmScreenBackground()
            .navigationTitle("Paste workout plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Paste") {
                        if let clipboard = UIPasteboard.general.string {
                            controller.pasteText = clipboard
                            controller.errorMessage = nil
                        }
                    }
                }
            }
            .sheet(isPresented: $controller.isShowingPreview) {
                WorkoutImportPreviewView(controller: controller) {
                    do {
                        let plan = try controller.buildPlan()
                        await onStartWorkout(plan, controller.saveAsTemplate)
                        controller.reset()
                        dismiss()
                    } catch {
                        controller.errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .helmTheme()
    }

    private var formatGuide: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text("Planner checklist")
                .helmFont(.label)
                .foregroundStyle(HelmColor.textPrimary)
            Text("[ ] exercise lines with • Sets, • Target Weight, • Intensity, and • Rest bullets. Weight and rep ranges import as midpoints.")
                .helmFont(.body)
                .foregroundStyle(HelmColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Hevy session log")
                .helmFont(.label)
                .foregroundStyle(HelmColor.textPrimary)
            Text("Exercise title, then set lines like Set 1: 20 kg x 8 @ 8 RPE, or one compressed line: Bench Press: 3 x 8 @ 80 kg.")
                .helmFont(.body)
                .foregroundStyle(HelmColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Gemini export tip")
                .helmFont(.label)
                .foregroundStyle(HelmColor.textPrimary)
            Text("Ask for a workout plan with concrete set counts and target weights. Checklist or flat log both work. Example: Dumbbell Shoulder Press: 3 x 8 @ 20 kg.")
                .helmFont(.body)
                .foregroundStyle(HelmColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(HelmSpacing.sm)
        .background(HelmColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: HelmRadius.md))
    }
}

#Preview {
    WorkoutImportView(
        controller: WorkoutImportController(persistence: try! PersistenceStore.inMemory()),
        onStartWorkout: { _, _ in }
    )
}
