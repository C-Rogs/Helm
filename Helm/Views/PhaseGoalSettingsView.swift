import Core
import DesignSystem
import HealthKitIngest
import Persistence
import PlanKit
import SwiftUI

struct PhaseGoalSettingsView: View {
    var embedInForm: Bool = true
    var saveButtonTitle: String = "Save & Re-plan"
    var showsInlineSaveButton: Bool = true
    var onSaved: (() -> Void)?
    var registerActions: ((PhaseGoalSettingsActions) -> Void)?

    @State private var settings = StoredTrainingPlanSettings.default
    @State private var weeklyRateText = ""
    @State private var emphasisText = ""
    @State private var saveMessage: String?
    @State private var isSaving = false
    @State private var isShowingCalculator = false
    @State private var loadedSettings = StoredTrainingPlanSettings.default
    @State private var pendingReactiveDeload = false
    @State private var reactiveDeloadMessage: String?
    @State private var showPlanBuilder = false

    private var prescriptionService: PrescriptionService { PlanBootstrap.prescriptionService }

    var body: some View {
        Group {
            if embedInForm {
                Form { formSections }
            } else {
                inlineContent
            }
        }
        .navigationTitle("Training Plan")
        .helmScreenBackground()
        .scrollContentBackground(.hidden)
        .task { await load() }
        .onAppear {
            registerActions?(PhaseGoalSettingsActions(
                saveIfNeeded: { await saveIfNeeded() },
                isDirty: { isDirty }
            ))
        }
        .sheet(isPresented: $isShowingCalculator) {
            WeeklyRateCalculatorSheet(initialPhase: settings.phaseGoal.phase) { rate, phase in
                settings.phaseGoal = PhaseGoal(
                    phase: phase,
                    weeklyRateKg: rate,
                    targetMass: settings.phaseGoal.targetMass,
                    emphasis: settings.phaseGoal.emphasis
                )
                weeklyRateText = String(format: "%.2f", rate)
                HapticEngine.shared.play(.selection)
            }
        }
        .sheet(isPresented: $showPlanBuilder) {
            PlanBuilderFlowView()
        }
    }

    @ViewBuilder
    private var inlineContent: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.lg) {
            Text("Changing phase re-plans today's session and future volume targets. Weekly rate is optional; you can set it later in Settings.")
                .font(HelmTypography.body)
                .foregroundStyle(HelmColor.fgSecondary)

            phaseFields

            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                Text("Experience")
                    .helmType(.label, color: HelmColor.fgSecondary)
                Picker("Training experience", selection: $settings.experienceRaw) {
                    Text("Novice").tag("novice")
                    Text("Intermediate").tag("intermediate")
                    Text("Advanced").tag("advanced")
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.experienceRaw) { _, _ in
                    HapticEngine.shared.play(.selection)
                }
            }

            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                Text("Session duration")
                    .helmType(.label, color: HelmColor.fgSecondary)
                Picker("Duration", selection: $settings.sessionDurationMinutes) {
                    ForEach(SessionDurationBudget.allCases) { budget in
                        Text(budget.label).tag(budget.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.sessionDurationMinutes) { _, _ in
                    HapticEngine.shared.play(.selection)
                }
            }

            if let saveMessage {
                Text(saveMessage)
                    .font(HelmTypography.caption)
                    .foregroundStyle(HelmColor.fgSecondary)
            }
        }
    }

    @ViewBuilder
    private var formSections: some View {
        Section {
            Text("Changing phase re-plans today's session and future volume targets. Weekly rate is optional; you can set it later in Settings.")
                .font(HelmType.body.font)
                .foregroundStyle(HelmColor.fgSecondary)
        }

        Section {
            Button("New workout plan") {
                HapticEngine.shared.play(.selection)
                showPlanBuilder = true
            }
        } footer: {
            Text("Rebuild days, volume, and session shape from an interview instead of editing phase fields here.")
                .font(HelmTypography.caption)
                .foregroundStyle(HelmColor.fgMuted)
        }

        Section("Phase") {
            phaseFields
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

        Section("Session shape") {
            Picker("Program", selection: $settings.programTemplateRaw) {
                ForEach(ProgramTemplate.allCases) { template in
                    Text(template.label).tag(template.rawValue)
                }
            }
            .onChange(of: settings.programTemplateRaw) { _, _ in
                HapticEngine.shared.play(.selection)
            }
            Text(ProgramTemplate(rawValue: settings.programTemplateRaw)?.detail ?? "")
                .font(HelmTypography.caption)
                .foregroundStyle(HelmColor.fgMuted)

            Picker("Duration", selection: $settings.sessionDurationMinutes) {
                ForEach(SessionDurationBudget.allCases) { budget in
                    Text(budget.label).tag(budget.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: settings.sessionDurationMinutes) { _, _ in
                HapticEngine.shared.play(.selection)
            }
            Text("Controls how many pattern slots and sets today's composer builds. Changing this re-plans incomplete days.")
                .font(HelmTypography.caption)
                .foregroundStyle(HelmColor.fgMuted)
        }

        if pendingReactiveDeload {
            Section("Recovery") {
                Text("Helm detected sustained low readiness. Confirm to start a reactive deload week at about half of peak volume with MEV floors held.")
                    .helmType(.body, color: HelmColor.fgSecondary)
                Button("Start reactive deload week", role: .destructive) {
                    Task { await confirmReactiveDeload() }
                }
                Button("Not now", role: .cancel) {
                    Task { await dismissReactiveDeload() }
                }
                if let reactiveDeloadMessage {
                    Text(reactiveDeloadMessage)
                        .helmType(.body, color: HelmColor.fgMuted)
                }
            }
        }

        if let saveMessage {
            Section {
                Text(saveMessage)
                    .foregroundStyle(HelmColor.fgSecondary)
            }
        }

        if showsInlineSaveButton {
            Section {
                saveButton
            }
        }
    }

    @ViewBuilder
    private var phaseFields: some View {
        Picker("Phase", selection: phaseBinding) {
            ForEach(TrainingPhase.allCases, id: \.self) { phase in
                Text(phase.label).tag(phase)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: settings.phaseGoal.phase) { _, _ in
            HapticEngine.shared.play(.phaseChange)
        }

        if settings.phaseGoal.phase != .maintain {
            VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                HStack {
                    TextField("Weekly rate (kg)", text: $weeklyRateText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: weeklyRateText) { _, _ in syncWeeklyRate() }
                    Button {
                        isShowingCalculator = true
                    } label: {
                        Image(systemName: "function")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Open rate calculator")
                }
                Text(WeeklyRateCalculator.safeRangeHint(for: settings.phaseGoal.phase))
                    .font(HelmTypography.caption)
                    .foregroundStyle(HelmColor.fgMuted)
            }
        }

        TextField("Emphasis", text: $emphasisText)
            .textFieldStyle(.roundedBorder)
            .onChange(of: emphasisText) { _, _ in syncEmphasis() }
    }

    @ViewBuilder
    private var saveButton: some View {
        HelmAsyncActionButton(saveButtonTitle, successTitle: "Saved") {
            await save()
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

    var isDirty: Bool {
        settings != loadedSettings
            || weeklyRateText != loadedWeeklyRateText
            || emphasisText != loadedEmphasisText
    }

    @MainActor
    func saveIfNeeded() async -> Bool {
        guard isDirty else { return true }
        await save()
        return saveMessage?.hasPrefix("Saved") == true
    }

    @MainActor
    private func load() async {
        do {
            settings = try await prescriptionService.currentTrainingPlan()
            loadedSettings = settings
            pendingReactiveDeload = try await prescriptionService.pendingReactiveDeload()
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
    private func confirmReactiveDeload() async {
        do {
            try await HelmActionRuntime.perform(
                .trainingPlan(.reactiveDeload(.confirm)),
                after: .none
            )
            pendingReactiveDeload = false
            reactiveDeloadMessage = "Reactive deload week confirmed. Today's session was re-planned."
            HapticEngine.shared.play(.phaseChange)
        } catch {
            reactiveDeloadMessage = error.localizedDescription
        }
    }

    @MainActor
    private func dismissReactiveDeload() async {
        do {
            try await HelmActionRuntime.perform(
                .trainingPlan(.reactiveDeload(.dismiss)),
                after: .none
            )
            pendingReactiveDeload = false
            reactiveDeloadMessage = "Reactive deload dismissed for now."
        } catch {
            reactiveDeloadMessage = error.localizedDescription
        }
    }

    @MainActor
    private func save() async -> Bool {
        isSaving = true
        defer { isSaving = false }
        syncWeeklyRate()
        syncEmphasis()

        do {
            try await HelmActionRuntime.perform(
                .trainingPlan(.replaceSettings(settings)),
                after: .none
            )
            loadedSettings = settings
            CloudBackupCoordinator.shared.schedulePush()
            HapticEngine.shared.play(.phaseChange)
            saveMessage = "Saved. Today's prescription was re-planned."
            onSaved?()
            return true
        } catch {
            saveMessage = error.localizedDescription
            return false
        }
    }

    private var loadedWeeklyRateText: String {
        if let rate = loadedSettings.phaseGoal.weeklyRateKg {
            return String(rate)
        }
        return ""
    }

    private var loadedEmphasisText: String {
        loadedSettings.phaseGoal.emphasis ?? ""
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

struct PhaseGoalSettingsActions {
    let saveIfNeeded: () async -> Bool
    let isDirty: () -> Bool
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
