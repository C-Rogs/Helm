import DesignSystem
import Persistence
import SwiftUI

struct WorkoutImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var controller: WorkoutImportController

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                Text("Paste a completed workout copied from Hevy or a planner. Helm parses exercises and sets, then saves the session to history.")
                    .font(HelmTypography.callout)
                    .foregroundStyle(HelmColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextEditor(text: $controller.pasteText)
                    .font(HelmTypography.body.monospaced())
                    .frame(minHeight: 220)
                    .padding(HelmSpacing.sm)
                    .background(HelmColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: HelmRadius.md))

                if let errorMessage = controller.errorMessage {
                    Text(errorMessage)
                        .font(HelmTypography.caption)
                        .foregroundStyle(HelmColor.destructive)
                }

                Spacer(minLength: 0)

                Button("Preview import") {
                    controller.parseForPreview()
                }
                .buttonStyle(.helmPrimary)
                .disabled(controller.pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(HelmSpacing.md)
            .helmScreenBackground()
            .navigationTitle("Import workout")
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
                    dismiss()
                }
            }
        }
        .helmTheme()
    }
}

#Preview {
    WorkoutImportView(controller: WorkoutImportController(persistence: try! PersistenceStore.inMemory()))
}
