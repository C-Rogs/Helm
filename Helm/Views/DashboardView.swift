import Core
import DesignSystem
import HealthKitIngest
import NutritionKit
import Persistence
import ReadinessKit
import SwiftUI

struct DashboardView: View {
    private var readinessService: ReadinessService { ReadinessBootstrap.readinessService }
    private var prescriptionService: PrescriptionService { PlanBootstrap.prescriptionService }
    private var briefService: BriefService { BriefBootstrap.briefService }
    @Bindable private var chatController = ChatBootstrap.controller
    private var thresholdInsightService: ThresholdInsightService { ProactiveBootstrap.thresholdInsightService }

    @Environment(\.helmReduceMotion) private var reduceMotion
    @State private var revealStore = ReadinessRevealStore()
    @State private var contributorDetailsVisible = true
    @State private var trainingPhase: TrainingPhase = .maintain
    @State private var bodyMassKg: Double?

    private var today: HelmDay {
        HelmDay.day(for: .now, calendar: .current)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                    greetingHeader
                    thresholdInsightCard
                    briefCard
                    readinessCard
                    prescriptionCard
                    nutritionTargetsCard

                    Button {
                        chatController.requestCoachHandoff(prompt: "What should I focus on today?")
                    } label: {
                        Label("Ask Coach", systemImage: "bubble.left.and.bubble.right")
                    }
                    .buttonStyle(.helmSecondary)
                }
                .padding(HelmSpacing.md)
            }
            .helmScreenBackground()
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await readinessService.refresh()
                await prescriptionService.refresh(readiness: readinessService.state.score)
                await briefService.refresh(
                    readiness: readinessService.state.score,
                    prescriptionSummary: prescriptionService.state.summary
                )
                await loadNutritionContext()
                await ProactiveBootstrap.refreshThresholdInsights()
            }
            .onChange(of: readinessService.state) { _, newState in
                Task {
                    await prescriptionService.refresh(readiness: newState.score)
                    await briefService.refresh(
                        readiness: newState.score,
                        prescriptionSummary: prescriptionService.state.summary
                    )
                    await ProactiveBootstrap.refreshThresholdInsights()
                }
            }
            .onChange(of: prescriptionService.state) { _, newState in
                Task {
                    await briefService.refresh(
                        readiness: readinessService.state.score,
                        prescriptionSummary: newState.summary
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var thresholdInsightCard: some View {
        if let insight = thresholdInsightService.currentInsight {
            ThresholdInsightCard(insight: insight)
        }
    }

    @ViewBuilder
    private var briefCard: some View {
        switch briefService.state {
        case .loading:
            briefShell(narration: "Building today's brief…", isEngineOnly: true, citationLabel: nil)
        case let .ready(model):
            briefShell(
                narration: model.narration,
                isEngineOnly: model.isEngineOnly,
                citationLabel: model.citationLabel
            )
        }
    }

    private func briefShell(narration: String, isEngineOnly: Bool, citationLabel: String?) -> some View {
        BriefCard(
            citationLabel: citationLabel,
            narration: narration,
            isEngineOnly: isEngineOnly
        )
    }

    @ViewBuilder
    private var prescriptionCard: some View {
        switch prescriptionService.state {
        case .loading:
            prescriptionShell(subtitle: "Loading…") {
                Text("Building today's session…")
                    .helmType(.body, color: HelmColor.fgMuted)
            }
        case .awaitingCatalog:
            prescriptionShell(subtitle: "Awaiting exercise catalog") {
                Text("Import exercises from Settings or finish first launch seeding.")
                    .helmType(.body, color: HelmColor.fgMuted)
                    .multilineTextAlignment(.leading)
            }
        case let .prescribed(summary):
            prescriptionShell(
                subtitle: prescriptionSubtitle(for: summary),
                phase: summary.phase
            ) {
                VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                    if summary.readinessAdjusted {
                        Text("Volume trimmed for readiness")
                            .helmType(.monoTag, color: HelmColor.depleted)
                    }

                    ForEach(summary.exercises) { exercise in
                        prescriptionExerciseRow(exercise)
                    }

                    HStack {
                        Text("\(summary.totalSets) total sets")
                            .helmType(.body, color: HelmColor.fgSecondary)
                        Spacer()
                        Text(summary.phase.label)
                            .helmType(.monoTag, color: HelmColor.fgMuted)
                    }
                    .explainable(
                        ExplainableMetricMappers.prescriptionVolume(
                            summary,
                            baselineSets: estimatedBaselineSets(for: summary),
                            coachAvailable: chatController.isCoachAvailable
                        ),
                        onAskCoach: chatController.requestCoachHandoff(prompt:)
                    )
                }
            }
        }
    }

    private func prescriptionShell<Content: View>(
        subtitle: String,
        phase: TrainingPhase? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                HStack {
                    Text("Today's Session")
                        .helmType(.label)
                    Spacer()
                    if let phase {
                        Text(phase.label)
                            .helmType(.monoTag, color: HelmColor.accent)
                            .padding(.horizontal, HelmSpacing.xs)
                            .padding(.vertical, HelmSpacing.xxs)
                            .background(HelmColor.accent.opacity(0.12), in: Capsule())
                    }
                }

                content()

                Text(subtitle)
                    .helmType(.body, color: HelmColor.fgMuted)
            }
        }
    }

    private func prescriptionExerciseRow(_ exercise: PrescribedExerciseSummary) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text(exercise.displayName)
                .helmType(.body)
            HStack(spacing: HelmSpacing.sm) {
                Text("\(exercise.targetSets) × \(exercise.targetRepRange)")
                    .helmType(.body, color: HelmColor.fgSecondary)
                if let load = exercise.targetLoad {
                    Text(load)
                        .helmType(.body, color: HelmColor.fgSecondary)
                }
                if let rpe = exercise.targetRPE {
                    Text(rpe)
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                }
            }
        }
        .padding(.vertical, HelmSpacing.xxs)
    }

    private func prescriptionSubtitle(for summary: PrescribedSessionSummary) -> String {
        var parts = ["\(summary.exercises.count) exercises"]
        if let emphasis = summary.emphasis, !emphasis.isEmpty {
            parts.append(emphasis)
        }
        return parts.joined(separator: " · ")
    }

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text(greetingText)
                .helmType(.title)
            Text("Today's readiness")
                .helmType(.body, color: HelmColor.fgSecondary)
        }
    }

    @ViewBuilder
    private var readinessCard: some View {
        switch readinessService.state {
        case .loading:
            readinessShell(subtitle: "Loading…") {
                placeholderArc(state: .compromised, subtitle: "Loading…")
            }
        case .awaitingData:
            readinessShell(subtitle: "Awaiting data") {
                placeholderArc(state: .compromised, subtitle: "Awaiting data")
            }
        case let .buildingBaseline(_, message):
            readinessShell(subtitle: message) {
                placeholderArc(state: .compromised, subtitle: message)
            }
        case let .scored(score):
            scoredReadinessCard(score: score)
        }
    }

    private func scoredReadinessCard(score: ReadinessScore) -> some View {
        let helmState = HelmState.readiness(score: Double(score.score))
        let shouldReveal = revealStore.shouldReveal(for: today)

        return readinessShell(
            subtitle: readinessSubtitle(for: score),
            state: helmState
        ) {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                ArcRevealGauge(
                    targetValue: Double(score.score),
                    state: helmState,
                    reveal: shouldReveal,
                    reduceMotion: reduceMotion,
                    detailsVisible: $contributorDetailsVisible,
                    onRevealStart: {
                        HapticEngine.shared.play(.readinessReveal)
                        revealStore.markRevealed(for: today)
                    }
                ) { displayValue in
                    VStack(spacing: HelmSpacing.xxs) {
                        Text("\(Int(displayValue.rounded()))")
                            .helmType(.heroNumber, color: HelmColor.color(for: helmState))
                        Text(helmState.label)
                            .helmType(.monoTag, color: HelmColor.fgMuted)
                        Text(confidenceLabel(for: score.confidence))
                            .helmType(.body, color: HelmColor.fgMuted)
                    }
                }
                .frame(maxWidth: 220)
                .frame(maxWidth: .infinity)
                .explainable(
                    ExplainableMetricMappers.readiness(
                        score,
                        coachAvailable: chatController.isCoachAvailable
                    ),
                    onAskCoach: chatController.requestCoachHandoff(prompt:)
                )
                .onAppear {
                    contributorDetailsVisible = !shouldReveal
                }

                contributorsCard(for: score)
                    .readinessDetailsReveal(visible: contributorDetailsVisible, reduceMotion: reduceMotion)
            }
        }
    }

    private func placeholderArc(state: HelmState, subtitle: String) -> some View {
        ArcGauge(value: 0, state: state) {
            VStack(spacing: HelmSpacing.xxs) {
                Text("--")
                    .helmType(.heroNumber, color: HelmColor.fgMuted)
                Text(state.label)
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                Text(subtitle)
                    .helmType(.body, color: HelmColor.fgMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: 220)
        .frame(maxWidth: .infinity)
    }

    private func readinessShell<Content: View>(
        subtitle: String,
        state: HelmState? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                HStack {
                    Text("ARC")
                        .helmType(.label)
                    Spacer()
                    if let state {
                        stateBadge(for: state)
                    }
                }

                content()

                Text(subtitle)
                    .helmType(.body, color: HelmColor.fgMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .overlay(alignment: .top) {
            if let state {
                RoundedRectangle(cornerRadius: HelmRadius.card)
                    .fill(HelmColor.color(for: state))
                    .frame(height: 3)
                    .padding(.horizontal, 1)
            }
        }
    }

    private func contributorsCard(for score: ReadinessScore) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text("Contributors")
                .helmType(.label)

            contributorBar("HRV", z: score.contributors.zHRV)
            contributorBar("Resting HR", z: score.contributors.zRestingHR)
            contributorBar("Sleep", z: score.contributors.zSleep)
            if score.contributors.zStrain != nil {
                contributorBar("Strain", z: score.contributors.zStrain)
            }
            if score.contributors.zRespiratory != nil {
                contributorBar("Respiratory", z: score.contributors.zRespiratory)
            }
            if score.contributors.zTemperature != nil {
                contributorBar("Temperature", z: score.contributors.zTemperature)
            }
        }
    }

    private func stateBadge(for state: HelmState) -> some View {
        Text(state.label)
            .helmType(.monoTag, color: HelmColor.color(for: state))
            .padding(.horizontal, HelmSpacing.xs)
            .padding(.vertical, HelmSpacing.xxs)
            .background(HelmColor.color(for: state).opacity(0.15), in: Capsule())
    }

    private func contributorBar(_ label: String, z: Double?) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            HStack {
                Text(label)
                    .helmType(.body, color: HelmColor.fgSecondary)
                Spacer()
                Text(contributorValueText(z))
                    .helmType(.body)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(HelmColor.gaugeTrack)
                    Capsule()
                        .fill(contributorFillColor(z))
                        .frame(width: geometry.size.width * contributorFillFraction(z))
                }
            }
            .frame(height: 6)

            if let detail = contributorDetail(z) {
                Text(detail)
                    .helmType(.body, color: HelmColor.fgMuted)
            }
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5 ..< 12: return "Good morning"
        case 12 ..< 17: return "Good afternoon"
        case 17 ..< 22: return "Good evening"
        default: return "Good night"
        }
    }

    private func readinessSubtitle(for score: ReadinessScore) -> String {
        if score.validNights < 14 {
            return "Provisional baseline (\(score.validNights)/14 nights)"
        }
        return "\(HelmState.readiness(score: Double(score.score)).label) · \(confidenceLabel(for: score.confidence))"
    }

    private func confidenceLabel(for confidence: ReadinessConfidence) -> String {
        switch confidence {
        case .high: "High confidence"
        case .medium: "Medium confidence"
        case .low: "Low confidence"
        }
    }

    private func contributorValueText(_ z: Double?) -> String {
        guard let z else { return "N/A" }
        let sign = z >= 0 ? "+" : ""
        return "z \(sign)\(String(format: "%.1f", z))"
    }

    private func contributorFillFraction(_ z: Double?) -> CGFloat {
        guard let z else { return 0 }
        let clamped = min(max(z, -2), 2)
        return CGFloat((clamped + 2) / 4)
    }

    private func contributorFillColor(_ z: Double?) -> Color {
        guard let z else { return HelmColor.fgMuted }
        if z > 0.75 { return HelmColor.primed }
        if z < -0.75 { return HelmColor.depleted }
        return HelmColor.accent
    }

    private func contributorDetail(_ z: Double?) -> String? {
        guard let z else { return "No data" }
        if z > 0.75 { return "Above baseline" }
        if z < -0.75 { return "Below baseline" }
        return "Near baseline"
    }

    @ViewBuilder
    private var nutritionTargetsCard: some View {
        let isTrainingDay = prescriptionService.state.summary != nil
        let dayType: NutritionDayType = isTrainingDay ? .training : .rest
        let targets = NutritionKit.targets(
            for: NutritionTargetContext(bodyMassKg: bodyMassKg, dayType: dayType),
            phase: PhaseGoal(phase: trainingPhase),
            trend: NutritionTrendState()
        ).summary

        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                Text("Nutrition targets")
                    .helmType(.label)

                HStack(alignment: .firstTextBaseline) {
                    Text("\(targets.caloriesKcal)")
                        .helmType(.bigNumber)
                    Text("kcal")
                        .helmType(.body, color: HelmColor.fgMuted)
                    Spacer()
                    Text(targets.dayType.capitalized)
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                }

                HStack(spacing: HelmSpacing.md) {
                    nutritionMacroChip("P", grams: targets.proteinGrams)
                    nutritionMacroChip("C", grams: targets.carbohydrateGrams)
                    nutritionMacroChip("F", grams: targets.fatGrams)
                }
            }
        }
        .explainable(
            ExplainableMetricMappers.nutrition(
                targets,
                phase: trainingPhase,
                coachAvailable: chatController.isCoachAvailable
            ),
            onAskCoach: chatController.requestCoachHandoff(prompt:)
        )
    }

    private func nutritionMacroChip(_ label: String, grams: Int) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text("\(grams)g")
                .helmType(.number)
            Text(label)
                .helmType(.monoTag, color: HelmColor.fgMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func estimatedBaselineSets(for summary: PrescribedSessionSummary) -> Int? {
        guard summary.readinessAdjusted else { return summary.totalSets }
        return summary.totalSets + 4
    }

    private func loadNutritionContext() async {
        let persistence = PersistenceBootstrap.persistenceStore
        do {
            let settings = try persistence.trainingPlan.load()
            trainingPhase = settings.phaseGoal.phase
            let latestBody = try persistence.bodyComposition.fetchLatest(
                onOrBefore: today,
                limit: 1
            ).first
            bodyMassKg = latestBody?.mass.kilograms
        } catch {
            trainingPhase = .maintain
            bodyMassKg = nil
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
    DashboardView()
        .helmTheme()
}
