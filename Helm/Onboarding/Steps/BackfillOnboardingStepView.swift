import DesignSystem
import HealthKitIngest
import SwiftUI

struct BackfillOnboardingStepView: View {
    var showsFlowControls: Bool = true
    var stepIndex: Int = 5
    var totalSteps: Int = OnboardingStep.allCases.count
    var onContinue: () -> Void = {}
    var onSkip: () -> Void = {}

    @State private var isBackfilling = false
    @State private var progress = BackfillProgress(
        completedChunks: 0,
        totalChunks: 0,
        samplesIngestedThisRun: 0,
        isComplete: false
    )
    @State private var hasStarted = false

    var body: some View {
        OnboardingStepChrome(
            step: .backfill,
            stepIndex: stepIndex,
            totalSteps: totalSteps,
            showsFlowControls: showsFlowControls,
            onPrimary: onContinue,
            onSkip: onSkip
        ) {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                if isBackfilling || hasStarted {
                    ProgressView(value: progressFraction)
                    Text(statusText)
                        .font(HelmTypography.body)
                        .foregroundStyle(HelmColor.fgSecondary)
                }

                Button(buttonTitle) {
                    Task { await runBackfill() }
                }
                .buttonStyle(.helmPrimary)
                .disabled(isBackfilling)
            }
            .padding(HelmSpacing.md)
            .background(HelmColor.surface, in: RoundedRectangle(cornerRadius: HelmRadius.md))
        }
        .task { await loadSavedProgress() }
    }

    private var buttonTitle: String {
        if isBackfilling { return "Importing…" }
        if progress.isComplete { return "Import complete" }
        return hasStarted ? "Resume import" : "Start import"
    }

    private var statusText: String {
        if progress.isComplete, progress.totalChunks > 0 {
            return "Imported \(progress.completedChunks) of \(progress.totalChunks) months."
        }
        if progress.totalChunks > 0 {
            return "Month \(progress.completedChunks) of \(progress.totalChunks)…"
        }
        return "Preparing import…"
    }

    private var progressFraction: Double {
        guard progress.totalChunks > 0 else { return progress.isComplete ? 1 : 0 }
        return Double(progress.completedChunks) / Double(progress.totalChunks)
    }

    private func loadSavedProgress() async {
        progress = await HealthKitBootstrap.backfillService.savedProgress()
        hasStarted = progress.completedChunks > 0 || progress.isComplete
    }

    private func runBackfill() async {
        isBackfilling = true
        hasStarted = true
        defer { isBackfilling = false }

        for await chunkProgress in await HealthKitBootstrap.backfillService.runDefaultIfNeeded() {
            progress = chunkProgress
        }
        await ReadinessBootstrap.readinessService.refresh()
        HapticEngine.shared.play(.selection)
    }
}

#Preview {
    BackfillOnboardingStepView()
        .helmTheme()
}
