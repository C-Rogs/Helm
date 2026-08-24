import CoachLLM
import Core
import DesignSystem
import HealthKitIngest
import PlanKit
import SwiftUI

/// One row in the refinement volume preview.
private struct VolumeRow: Identifiable {
    let muscle: MuscleGroup
    let sets: Int
    let frequency: Int

    var id: String { muscle.rawValue }
}

/// Deep review of the picked option: week preview, volume table, dials, commit.
struct PlanRefinementView: View {
    let option: PlanBuilderOption
    let interview: PlanBuilderInterview
    let service: PlanBuilderService
    let onCommitted: () -> Void
    let onBack: () -> Void

    @State private var daysPerWeek: Int
    @State private var sessionMinutes: Int
    @State private var isCommitting = false
    @State private var errorMessage: String?
    /// Recomputed candidate when dials change.
    @State private var refined: CandidatePlan

    private var prescriptionService: PrescriptionService { PlanBootstrap.prescriptionService }

    init(
        option: PlanBuilderOption,
        interview: PlanBuilderInterview,
        service: PlanBuilderService,
        onCommitted: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) {
        self.option = option
        self.interview = interview
        self.service = service
        self.onCommitted = onCommitted
        self.onBack = onBack
        _daysPerWeek = State(initialValue: option.candidate.daysPerWeek)
        _sessionMinutes = State(initialValue: option.candidate.sessionDurationMinutes)
        _refined = State(initialValue: option.candidate)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                Text(option.candidate.headline)
                    .helmType(.title, color: HelmColor.fg)

                Text(option.copy.outcome)
                    .helmType(.body, color: HelmColor.fgSecondary)

                dials

                if dialsChanged {
                    Text("Adjusted from the drafted option. Volume below reflects your changes; coach notes still describe the original.")
                        .font(HelmTypography.caption)
                        .foregroundStyle(HelmColor.fgMuted)
                }

                volumePreview

                if !option.copy.benefits.isEmpty || !option.copy.challenges.isEmpty {
                    tradeoffs
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(HelmTypography.caption)
                        .foregroundStyle(HelmColor.fgMuted)
                }

                Button {
                    Task { await commit() }
                } label: {
                    if isCommitting {
                        ProgressView()
                            .tint(HelmColor.buttonPrimaryForeground)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Lock in this plan")
                    }
                }
                .buttonStyle(.helmPrimary)
                .disabled(isCommitting)

                Button("Back to options") {
                    onBack()
                }
                .buttonStyle(.helmSecondary)
            }
            .padding(HelmSpacing.screenGutter)
        }
        .onChange(of: daysPerWeek) { _, _ in regenerate() }
        .onChange(of: sessionMinutes) { _, _ in regenerate() }
    }

    // MARK: - Dials

    private var dials: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.md) {
            Text("Adjust")
                .helmType(.label, color: HelmColor.fgSecondary)

            Stepper(value: $daysPerWeek, in: 2 ... 6) {
                HStack {
                    Text("Days per week")
                        .helmType(.body, color: HelmColor.fg)
                    Spacer()
                    Text("\(daysPerWeek)")
                        .helmType(.number, color: HelmColor.accent)
                }
            }

            Picker("Session length", selection: $sessionMinutes) {
                ForEach(SessionDurationBudget.allCases) { budget in
                    Text(budget.label).tag(budget.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: sessionMinutes) { _, _ in
                HapticEngine.shared.play(.selection)
            }
        }
        .padding(HelmSpacing.md)
        .background(HelmColor.surface, in: RoundedRectangle(cornerRadius: HelmRadius.md))
    }

    // MARK: - Week preview + volume

    private var volumePreview: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text("Peak weekly hard sets")
                .helmType(.label, color: HelmColor.fgSecondary)

            ForEach(volumeRows) { row in
                HStack {
                    Text(row.muscle.rawValue.capitalized)
                        .helmType(.body, color: HelmColor.fg)
                    Spacer()
                    Text("\(row.sets) sets")
                        .helmType(.monoTag, color: HelmColor.fgSecondary)
                    Text("\(row.frequency)x / wk")
                        .font(HelmTypography.caption)
                        .foregroundStyle(HelmColor.fgMuted)
                        .frame(width: 70, alignment: .trailing)
                }
            }

            if interview.experienceRaw == "novice" {
                Text("Loads start conservative and calibrate from your first logged sessions. No separate strength testing needed before starting.")
                    .font(HelmTypography.caption)
                    .foregroundStyle(HelmColor.fgMuted)
            }
        }
        .padding(HelmSpacing.md)
        .background(HelmColor.surface, in: RoundedRectangle(cornerRadius: HelmRadius.md))
    }

    private var tradeoffs: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            if !option.copy.benefits.isEmpty {
                ForEach(option.copy.benefits, id: \.self) { benefit in
                    Label(benefit, systemImage: "checkmark.circle")
                        .helmType(.body, color: HelmColor.fgSecondary)
                }
            }
            if !option.copy.challenges.isEmpty {
                ForEach(option.copy.challenges, id: \.self) { challenge in
                    Label(challenge, systemImage: "exclamationmark.circle")
                        .helmType(.body, color: HelmColor.fgSecondary)
                }
            }
        }
        .padding(HelmSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HelmColor.surface, in: RoundedRectangle(cornerRadius: HelmRadius.md))
    }

    private var dialsChanged: Bool {
        daysPerWeek != option.candidate.daysPerWeek
            || sessionMinutes != option.candidate.sessionDurationMinutes
    }

    private var volumeRows: [VolumeRow] {
        refined.weeklyPeakSetsByMuscle
            .sorted { $0.value > $1.value }
            .map { muscle, sets in
                VolumeRow(muscle: muscle, sets: sets, frequency: refined.frequencyByMuscle[muscle] ?? 0)
            }
    }

    private func regenerate() {
        HapticEngine.shared.play(.selection)
        var adjustedInterview = interview
        adjustedInterview.daysPerWeek = daysPerWeek
        adjustedInterview.sessionDurationMinutes = sessionMinutes
        let adjustedCandidates = CandidatePlanGenerator.generate(
            interview: adjustedInterview,
            experience: CandidatePlanGenerator.experience(of: adjustedInterview)
        )
        // Keep the same blueprint family when available; else closest fit.
        let sameFamily = adjustedCandidates.first { $0.id == option.candidate.id }
        let bestFit = adjustedCandidates.max { $0.availabilityFitScore < $1.availabilityFitScore }
        refined = sameFamily ?? bestFit ?? option.candidate
    }

    private func commit() async {
        isCommitting = true
        defer { isCommitting = false }
        var finalInterview = interview
        finalInterview.daysPerWeek = daysPerWeek
        finalInterview.sessionDurationMinutes = sessionMinutes
        do {
            let chosen = PlanBuilderOption(candidate: refined, copy: option.copy)
            let settings = try service.makeUpdatedSettings(option: chosen, interview: finalInterview)
            try await prescriptionService.saveTrainingPlan(settings)
            service.clearSession()
            HapticEngine.shared.play(.phaseChange)
            onCommitted()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
