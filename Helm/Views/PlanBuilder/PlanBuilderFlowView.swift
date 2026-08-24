import Core
import DesignSystem
import HealthKitIngest
import Persistence
import PlanKit
import SwiftUI

/// Standalone coach plan-builder flow: interview -> option cards -> refine -> commit.
struct PlanBuilderFlowView: View {
    enum Stage {
        case interview
        case thinking
        case cards
        case refine(PlanBuilderOption)
    }

    @State private var stage: Stage = .interview
    @State private var interview = PlanBuilderInterview()
    @State private var maintenanceText = ""
    @State private var selectedDays: Set<String> = ["3"]
    @State private var selectedDuration: Set<String> = ["60"]
    @State private var selectedExperience: Set<String> = ["intermediate"]
    @State private var selectedGoal: Set<String> = [PlanBuilderInterview.ProgressionGoal.hypertrophy.rawValue]
    @State private var emphasisText = ""
    @State private var options: [PlanBuilderOption] = []
    @State private var notice: String?
    @State private var showCommittedConfirmation = false

    private let service = PlanBuilderService(
        persistence: PersistenceBootstrap.persistenceStore,
        provider: CoachBootstrap.liveGeminiProvider
    )

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .interview:
                    interviewView
                case .thinking:
                    thinkingView
                case .cards:
                    PlanOptionCardsView(options: options) { option in
                        HapticEngine.shared.play(.coachAdjust)
                        withAnimation {
                            stage = .refine(option)
                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        Button("Back to questions") {
                            stage = .interview
                        }
                        .buttonStyle(.helmSecondary)
                        .padding(.horizontal, HelmSpacing.screenGutter)
                        .padding(.bottom, HelmSpacing.sm)
                    }
                case .refine(let option):
                    PlanRefinementView(
                        option: option,
                        interview: syncedInterview(),
                        service: service,
                        onCommitted: {
                            HapticEngine.shared.play(.sessionFinished)
                            PlanBootstrap.refreshPrescription()
                            NutritionBootstrap.refreshNutrition()
                            CloudBackupCoordinator.shared.schedulePush()
                            showCommittedConfirmation = true
                            options = []
                            stage = .interview
                        },
                        onBack: { stage = .cards }
                    )
                }
            }
            .navigationTitle("Plan Builder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isInterviewStage {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            stage = .interview
                        }
                    }
                }
            }
            .helmScreenBackground()
        }
        .task {
            if let resumable = service.loadResumableSession() {
                applyInterview(resumable.interview)
                // A completed generation pass resumes straight at the cards.
                if let restoredOptions = service.restoredOptions() {
                    options = restoredOptions
                    stage = .cards
                }
            } else {
                applyInterview(service.makePrefilledInterview())
            }
        }
        .alert("Plan locked in", isPresented: $showCommittedConfirmation) {
            Button("Done", role: .cancel) {}
        } message: {
            Text("Your training plan was updated and today's session re-prescribed. Your coach chat can see the new plan too.")
        }
    }

    /// Interview state assembled from the current answer pickers.
    private func syncedInterview() -> PlanBuilderInterview {
        syncInterview()
        return interview
    }

    private var isInterviewStage: Bool {
        if case .interview = stage { return true }
        return false
    }

    private func applyInterview(_ value: PlanBuilderInterview) {
        interview = value
        selectedDays = [String(value.daysPerWeek)]
        selectedDuration = [String(value.sessionDurationMinutes)]
        selectedExperience = [value.experienceRaw]
        selectedGoal = [value.progressionGoal.rawValue]
        emphasisText = value.emphasis ?? ""
        if let kcal = value.confirmedMaintenanceKcal {
            maintenanceText = String(Int(kcal))
        }
    }

    // MARK: - Interview

    private var interviewView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                Text("Confirm what Helm knows, then I will draft plan options.")
                    .helmType(.body, color: HelmColor.fgSecondary)

                MultipleChoiceQuestionView(
                    question: "How many days per week can you train?",
                    options: [
                        MCQOption(id: "2", label: "Two days"),
                        MCQOption(id: "3", label: "Three days"),
                        MCQOption(id: "4", label: "Four days"),
                        MCQOption(id: "5", label: "Five days"),
                        MCQOption(id: "6", label: "Six days")
                    ],
                    selection: $selectedDays
                )

                MultipleChoiceQuestionView(
                    question: "Session length?",
                    options: [
                        MCQOption(id: "30", label: "30 minutes"),
                        MCQOption(id: "45", label: "45 minutes"),
                        MCQOption(id: "60", label: "60 minutes"),
                        MCQOption(id: "75", label: "75+ minutes")
                    ],
                    selection: $selectedDuration
                )

                MultipleChoiceQuestionView(
                    question: "Years of consistent lifting?",
                    options: [
                        MCQOption(id: "novice", label: "Under 1 year", detail: "Landmarks seed conservatively."),
                        MCQOption(id: "intermediate", label: "1 to 3 years", detail: "Standard landmark scaling."),
                        MCQOption(id: "advanced", label: "Over 3 years", detail: "Higher volume tolerance assumed.")
                    ],
                    selection: $selectedExperience
                )

                MultipleChoiceQuestionView(
                    question: "Primary goal this block?",
                    options: PlanBuilderInterview.ProgressionGoal.allCases.map { goal in
                        MCQOption(id: goal.rawValue, label: goal.label, detail: goal.detail)
                    },
                    selection: $selectedGoal
                )

                VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                    Text("Maintenance calories")
                        .helmType(.label, color: HelmColor.fgSecondary)
                    TextField("kcal / day", text: $maintenanceText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Text("Pre-filled from your body profile estimate. Adjust if your own tracking disagrees.")
                        .font(HelmTypography.caption)
                        .foregroundStyle(HelmColor.fgMuted)
                }

                VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                    Text("Emphasis (optional)")
                        .helmType(.label, color: HelmColor.fgSecondary)
                    TextField("e.g. arms, v-taper", text: $emphasisText)
                        .textFieldStyle(.roundedBorder)
                }

                if let notice {
                    Text(notice)
                        .font(HelmTypography.caption)
                        .foregroundStyle(HelmColor.fgMuted)
                }

                Button("Draft my plan options") {
                    syncInterview()
                    Task { await generate() }
                }
                .buttonStyle(.helmPrimary)
                .disabled(!isInterviewValid)
            }
            .padding(HelmSpacing.screenGutter)
        }
    }

    private var isInterviewValid: Bool {
        !selectedDays.isEmpty && !selectedDuration.isEmpty && !selectedGoal.isEmpty && !selectedExperience.isEmpty
    }

    private func syncInterview() {
        interview.daysPerWeek = Int(selectedDays.first ?? "") ?? 3
        interview.sessionDurationMinutes = Int(selectedDuration.first ?? "") ?? 60
        interview.experienceRaw = selectedExperience.first ?? "intermediate"
        interview.progressionGoal = PlanBuilderInterview.ProgressionGoal(rawValue: selectedGoal.first ?? "")
            ?? .hypertrophy
        let trimmedKcal = maintenanceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let kcal = Double(trimmedKcal), kcal > 500, kcal < 8000 {
            interview.confirmedMaintenanceKcal = kcal
        } else {
            interview.confirmedMaintenanceKcal = nil
        }
        let trimmedEmphasis = emphasisText.trimmingCharacters(in: .whitespacesAndNewlines)
        interview.emphasis = trimmedEmphasis.isEmpty ? nil : trimmedEmphasis
    }

    private func generate() async {
        stage = .thinking
        await service.generateOptions(for: interview)
        options = service.options
        notice = service.generationMessage
        if options.isEmpty {
            stage = .interview
        } else {
            HapticEngine.shared.play(.thresholdInsight)
            service.saveResumableState(interview: interview, options: options)
            stage = .cards
        }
    }

    // MARK: - Thinking

    private var thinkingView: some View {
        VStack(spacing: HelmSpacing.lg) {
            Spacer()
            CoachAIProgressCard(
                eyebrow: "COACH",
                title: "Drafting plan options",
                completedSteps: [
                    "Confirmed metrics and preferences",
                    "Computed candidate volumes from engine landmarks"
                ],
                currentStep: "Writing outcome copy for each option…",
                footnote: "Candidates come from Helm's planning engine. The coach adds outcome copy grounded in current evidence.",
                isImpactful: true
            )
            Spacer()
            Button("Cancel") {
                stage = .interview
            }
            .buttonStyle(.helmSecondary)
        }
        .padding(HelmSpacing.screenGutter)
    }
}

#Preview("Flow") {
    PlanBuilderFlowView()
}
