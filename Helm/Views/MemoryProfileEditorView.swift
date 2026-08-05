import CoachLLM
import Core
import DesignSystem
import Persistence
import SwiftUI

struct MemoryProfileEditorView: View {
    @State private var profile = MemoryProfile.empty
    @State private var saveMessage: String?
    @State private var isSaving = false

    var body: some View {
        Form {
            Section {
                Text("Coach reads this memory every turn. Edit freely; changes apply on the next chat.")
                    .font(HelmType.body.font)
                    .foregroundStyle(HelmColor.fgSecondary)
            }

            Section("Baselines") {
                editorField("Summary", text: $profile.baselinesSummary)
            }

            Section("Mesocycle") {
                editorField("Position", text: $profile.mesocyclePosition)
            }

            Section("Phase") {
                Text("Edit phase, rate, and emphasis under Settings → Training Plan.")
                    .font(HelmType.body.font)
                    .foregroundStyle(HelmColor.fgSecondary)
                if let phaseGoal = profile.phaseGoal {
                    LabeledContent("Current phase", value: phaseGoal.phase.label)
                    if let emphasis = phaseGoal.emphasis, !emphasis.isEmpty {
                        LabeledContent("Emphasis", value: emphasis)
                    }
                }
            }

            Section("Preferences") {
                editorField("Notes", text: $profile.preferences)
            }

            Section("Standing Constraints") {
                editorField("Constraints", text: $profile.standingConstraints)
                Text("Temporary recovery notes use dated lines with until/joint tags. Coach can save these via chat confirm. Example: 2026-08-05 [until:2026-08-08] [joint:shoulder] Soft pause overhead pressing.")
                    .font(HelmTypography.caption)
                    .foregroundStyle(HelmColor.fgSecondary)
            }

            Section("What Has Worked") {
                editorField("Notes", text: $profile.whatHasWorked)
            }

            if let saveMessage {
                Section {
                    Text(saveMessage)
                        .foregroundStyle(HelmColor.fgSecondary)
                }
            }

            Section {
                Button(isSaving ? "Saving…" : "Save Memory") {
                    Task { await save() }
                }
                .disabled(isSaving)
            }
        }
        .navigationTitle("Coach Memory")
        .helmScreenBackground()
        .task { await load() }
    }

    @ViewBuilder
    private func editorField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            Text(title)
                .font(HelmType.monoTag.font)
                .foregroundStyle(HelmColor.fgMuted)
            TextEditor(text: text)
                .frame(minHeight: HelmSpacing.xl * 2 + HelmSpacing.lg)
                .scrollContentBackground(.hidden)
                .padding(HelmSpacing.xs)
                .background(HelmColor.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: HelmRadius.sm))
        }
        .listRowBackground(HelmColor.surface)
    }

    @MainActor
    private func load() async {
        do {
            let loaded = try PersistenceBootstrap.persistenceStore.memoryProfile.load()
            profile = loaded
        } catch {
            saveMessage = error.localizedDescription
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try PersistenceBootstrap.persistenceStore.memoryProfile.save(profile)
            HapticEngine.shared.play(.coachAdjust)
            saveMessage = "Saved. Coach will use this on the next turn."
        } catch {
            saveMessage = error.localizedDescription
        }
    }
}

private extension TrainingPhase {
    var label: String {
        switch self {
        case .cut: "Cut"
        case .maintain: "Maintain"
        case .gain: "Gain"
        }
    }
}

#Preview {
    NavigationStack {
        MemoryProfileEditorView()
    }
    .helmTheme()
}
