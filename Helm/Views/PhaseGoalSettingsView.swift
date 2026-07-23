import Core
import DesignSystem
import HealthKitIngest
import Persistence
import SwiftUI

struct PhaseGoalSettingsView: View {
    var embedInForm: Bool = true
    var saveButtonTitle: String = "Save & Re-plan"
    var onSaved: (() -> Void)?

    @State private var settings = StoredTrainingPlanSettings.default
    @State private var weeklyRateText = ""
    @State private var emphasisText = ""
    @State private var saveMessage: String?
    @State private var isSaving = false

    private var prescriptionService: PrescriptionService { PlanBootstrap.prescriptionService }

    var body: some View {
        Group {
            if embedInForm {
                Form { settingsContent }
            } else {
                settingsContent
            }
        }
        .navigationTitle("Training Plan")
        .helmScreenBackground()
        .task { await load() }
    }

    @ViewBuilder
    private var settingsContent: some View {
        Group {
            Section {
                Text("Changing phase re-plans today's session and future volume targets.")
                    .font(HelmType.body.font)
                    .foregroundStyle(HelmColor.fgSecondary)
            }

            Section("Phase") {
                Picker("Phase", selection: phaseBinding) {
                    ForEach(TrainingPhase.allCases, id: \.self) { phase in
                        Text(phase.label).tag(phase)
                    }
                }
                .onChange(of: settings.phaseGoal.phase) { _, _ in
                    HapticEngine.shared.play(.phaseChange)
                }

                if settings.phaseGoal.phase != .maintain {
                    TextField("Weekly rate (kg)", text: $weeklyRateText)
                        .keyboardType(.decimalPad)
                        .onChange(of: weeklyRateText) { _, _ in syncWeeklyRate() }
                }

                TextField("Emphasis", text: $emphasisText)
                    .onChange(of: emphasisText) { _, _ in syncEmphasis() }
            }

            Section("Experience") {
                Picker("Training experience", selection: $settings.experienceRaw) {
                    Text("Novice").tag("novice")
                    Text("Intermediate").tag("intermediate")
                    Text("Advanced").tag("advanced")
                }
                .onChange(of: settings.experienceRaw) { _, _ in
                    HapticEngine.shared.play(.selection)
                }
            }

            if let saveMessage {
                Section {
                    Text(saveMessage)
                        .foregroundStyle(HelmColor.fgSecondary)
                }
            }

            if embedInForm {
                Section {
                    saveButton
                }
            } else {
                saveButton
            }
        }
    }

    @ViewBuilder
    private var saveButton: some View {
        if embedInForm {
            Button(isSaving ? "Saving…" : saveButtonTitle) {
                Task { await save() }
            }
            .buttonStyle(.borderless)
            .disabled(isSaving)
        } else {
            Button(isSaving ? "Saving…" : saveButtonTitle) {
                Task { await save() }
            }
            .buttonStyle(.helmPrimary)
            .disabled(isSaving)
        }
    }

    private var phaseBinding: Binding<TrainingPhase> {
        Binding(
            get: { settings.phaseGoal.phase },
            set: { newPhase in
                settings.phaseGoal = PhaseGoal(
                    phase: newPhase,
                    weeklyRateKg: settings.phaseGoal.weeklyRateKg,
                    targetMass: settings.phaseGoal.targetMass,
                    emphasis: settings.phaseGoal.emphasis
                )
            }
        )
    }

    @MainActor
    private func load() async {
        do {
            settings = try await prescriptionService.currentTrainingPlan()
            if let rate = settings.phaseGoal.weeklyRateKg {
                weeklyRateText = String(rate)
            } else {
                weeklyRateText = ""
            }
            emphasisText = settings.phaseGoal.emphasis ?? ""
        } catch {
            saveMessage = error.localizedDescription
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        syncWeeklyRate()
        syncEmphasis()

        do {
            try await prescriptionService.saveTrainingPlan(settings)
            HapticEngine.shared.play(.phaseChange)
            saveMessage = "Saved. Today's prescription was re-planned."
            PlanBootstrap.refreshPrescription()
            onSaved?()
        } catch {
            saveMessage = error.localizedDescription
        }
    }

    private func syncWeeklyRate() {
        let trimmed = weeklyRateText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rate = trimmed.isEmpty ? nil : Double(trimmed)
        settings.phaseGoal = PhaseGoal(
            phase: settings.phaseGoal.phase,
            weeklyRateKg: rate,
            targetMass: settings.phaseGoal.targetMass,
            emphasis: settings.phaseGoal.emphasis
        )
    }

    private func syncEmphasis() {
        let trimmed = emphasisText.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.phaseGoal = PhaseGoal(
            phase: settings.phaseGoal.phase,
            weeklyRateKg: settings.phaseGoal.weeklyRateKg,
            targetMass: settings.phaseGoal.targetMass,
            emphasis: trimmed.isEmpty ? nil : trimmed
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
        PhaseGoalSettingsView()
    }
    .helmTheme()
}
