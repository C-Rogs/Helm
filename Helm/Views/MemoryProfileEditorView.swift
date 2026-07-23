import CoachLLM
import Core
import DesignSystem
import Persistence
import SwiftUI

struct MemoryProfileEditorView: View {
    @State private var profile = MemoryProfile.empty
    @State private var selectedPhase: TrainingPhase = .maintain
    @State private var weeklyRateText = ""
    @State private var emphasisText = ""
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
                Picker("Phase", selection: $selectedPhase) {
                    ForEach(TrainingPhase.allCases, id: \.self) { phase in
                        Text(phase.label).tag(phase)
                    }
                }
                .onChange(of: selectedPhase) { _, _ in
                    HapticEngine.shared.play(.selection)
                    syncPhaseGoal()
                }

                TextField("Weekly rate (kg)", text: $weeklyRateText)
                    .keyboardType(.decimalPad)
                    .onChange(of: weeklyRateText) { _, _ in syncPhaseGoal() }

                TextField("Emphasis", text: $emphasisText)
                    .onChange(of: emphasisText) { _, _ in syncPhaseGoal() }
            }

            Section("Preferences") {
                editorField("Notes", text: $profile.preferences)
            }

            Section("Standing Constraints") {
                editorField("Constraints", text: $profile.standingConstraints)
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
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(HelmType.monoTag.font)
                .foregroundStyle(HelmColor.fgMuted)
            TextEditor(text: text)
                .frame(minHeight: 88)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(HelmColor.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .listRowBackground(HelmColor.surface)
    }

    @MainActor
    private func load() async {
        do {
            let loaded = try PersistenceBootstrap.persistenceStore.memoryProfile.load()
            profile = loaded
            selectedPhase = loaded.phaseGoal?.phase ?? .maintain
            if let rate = loaded.phaseGoal?.weeklyRateKg {
                weeklyRateText = String(rate)
            } else {
                weeklyRateText = ""
            }
            emphasisText = loaded.phaseGoal?.emphasis ?? ""
        } catch {
            saveMessage = error.localizedDescription
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        syncPhaseGoal()
        do {
            try PersistenceBootstrap.persistenceStore.memoryProfile.save(profile)
            HapticEngine.shared.play(.coachAdjust)
            saveMessage = "Saved. Coach will use this on the next turn."
        } catch {
            saveMessage = error.localizedDescription
        }
    }

    private func syncPhaseGoal() {
        let rate = Double(weeklyRateText.trimmingCharacters(in: .whitespacesAndNewlines))
        let emphasis = emphasisText.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.phaseGoal = PhaseGoal(
            phase: selectedPhase,
            weeklyRateKg: rate,
            emphasis: emphasis.isEmpty ? nil : emphasis
        )
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
