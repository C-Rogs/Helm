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
    @State private var selectedGoal: Set<String> = [PlanBuilderInterview.ProgressionGoal.hypertrophy.rawValue]
    @State private var emphasisText = ""
    @State private var options: [PlanBuilderOption] = []
    @State private var notice: String?

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
                        stage = .refine(option)
                    }
                case .refine(let option):
                    PlanRefinementView(
                        option: option,
                        interview: interview,
                        service: service,
                        onCommitted: {
                            PlanBootstrap.refreshPrescription()
                            NutritionBootstrap.refreshNutrition()
                            CloudBackupCoordinator.shared.schedulePush()
                            stage = .interview
                            options = []
                        },
                        onBack: { stage = .cards }
                    )
                }
            }
            .navigationTitle("Plan Builder")
            .navigationBarTitleDisplayMode(.inline)
            .helmScreenBackground()
        }
        .task {
            if let resumable = service.loadResumableSession() {
                applyInterview(resumable.interview)
            } else {
                applyInterview(service.makePrefilledInterview())
            }
        }
    }

    private func applyInterview(_ value: PlanBuilderInterview) {
        interview = value
        selectedDays = [String(value.daysPerWeek)]
        selectedDuration = [String(value.sessionDurationMinutes)]
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
        !selectedDays.isEmpty && !selectedDuration.isEmpty && !selectedGoal.isEmpty
    }

    private func syncInterview() {
        interview.daysPerWeek = Int(selectedDays.first ?? "") ?? 3
        interview.sessionDurationMinutes = Int(selectedDuration.first ?? "") ?? 60
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
            service.saveSession(StoredPlanBuilderSession(interview: interview))
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
                currentStep: "Cross-referencing against training research…",
                footnote: "Candidates come from Helm's planning engine. The coach adds outcome copy grounded in current evidence.",
                isImpactful: true
            )
            Spacer()
        }
        .padding(HelmSpacing.screenGutter)
    }
}

#Preview("Flow") {
    PlanBuilderFlowView()
}
