import Core
import DesignSystem
import SwiftUI

struct PawelTimerModal: View {
    let controller: TrainSessionController

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPresetSeconds = 90
    @State private var isMutating = false

    private let presets = [60, 90, 120, 180]

    private var isRunning: Bool {
        controller.isRestTimerRunning
    }

    private var restTimer: RestTimer? {
        controller.snapshot?.restTimer
    }

    /// True when the running timer duration matches the selected preset.
    private var selectedPresetIsActive: Bool {
        guard isRunning, let timer = restTimer else { return false }
        return timer.defaultDurationSeconds == selectedPresetSeconds
            && presets.contains(selectedPresetSeconds)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: HelmSpacing.lg) {
                timerRingSection
                primaryActionButton
                presetGrid
                Spacer(minLength: 0)
            }
            .padding(HelmSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .helmScreenBackground()
            .navigationTitle("Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .disabled(isMutating)
            .onAppear { syncSelectedPresetFromRunningTimer() }
            .onChange(of: restTimer?.id) { _, _ in
                syncSelectedPresetFromRunningTimer()
            }
            .onChange(of: restTimer?.defaultDurationSeconds) { _, _ in
                syncSelectedPresetFromRunningTimer()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var timerRingSection: some View {
        if isRunning, let timer = restTimer, let endsAt = timer.endsAt {
            let totalSeconds = controller.restTimerTotalSeconds(for: timer)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, Int(endsAt.timeIntervalSince(context.date).rounded(.down)))
                let fraction = RestTimerBannerProgress.remainingFraction(
                    remainingSeconds: remaining,
                    totalSeconds: totalSeconds
                )
                RadialCountdownRing(
                    remainingSeconds: remaining,
                    remainingFraction: fraction
                )
                .frame(maxWidth: 240)
                .padding(HelmSpacing.md)
                .helmPanelChrome(.accentQuiet, cornerRadius: HelmRadius.lg)
            }
        } else {
            RadialCountdownRing(
                remainingSeconds: selectedPresetSeconds,
                remainingFraction: 1
            )
            .frame(maxWidth: 240)
            .padding(HelmSpacing.md)
            .helmPanelChrome(.accentQuiet, cornerRadius: HelmRadius.lg)
        }
    }

    private var primaryActionButton: some View {
        Button {
            runMutation {
                if isRunning {
                    await controller.skipRest()
                } else {
                    await controller.startManualRest(durationSeconds: selectedPresetSeconds)
                }
            }
        } label: {
            Text(isRunning ? "Stop" : "Start")
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
        }
        .buttonStyle(.helmPrimary)
        .disabled(isMutating)
        .accessibilityLabel(isRunning ? "Stop timer" : "Start timer")
    }

    private var presetGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: HelmSpacing.sm) {
            ForEach(presets, id: \.self) { seconds in
                let isSelected = seconds == selectedPresetSeconds
                let showActive = isSelected && selectedPresetIsActive
                Button {
                    handlePresetTap(seconds)
                } label: {
                    VStack(spacing: HelmSpacing.xxs) {
                        Text("\(seconds)s")
                            .helmType(.bigNumber, color: isSelected ? HelmColor.accent : HelmColor.fg)
                        if showActive {
                            Text("Active")
                                .helmType(.monoTag, color: HelmColor.accent)
                        } else if isSelected && !isRunning {
                            Text("Selected")
                                .helmType(.monoTag, color: HelmColor.accent)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 72)
                    .padding(HelmSpacing.md)
                    .background(HelmColor.surfaceElevated, in: RoundedRectangle(cornerRadius: HelmRadius.md))
                    .overlay {
                        RoundedRectangle(cornerRadius: HelmRadius.md)
                            .strokeBorder(
                                isSelected ? HelmColor.accent.opacity(0.45) : HelmColor.hairline,
                                lineWidth: 1
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(isMutating)
                .accessibilityLabel("\(seconds) seconds")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private func handlePresetTap(_ seconds: Int) {
        if isRunning {
            selectedPresetSeconds = seconds
            runMutation {
                await controller.startManualRest(durationSeconds: seconds)
            }
        } else {
            HapticEngine.shared.play(.selection)
            selectedPresetSeconds = seconds
        }
    }

    private func runMutation(_ work: @escaping @MainActor () async -> Void) {
        guard !isMutating else { return }
        isMutating = true
        Task {
            await work()
            isMutating = false
        }
    }

    private func syncSelectedPresetFromRunningTimer() {
        guard let timer = restTimer, isRunning else { return }
        let duration = timer.defaultDurationSeconds
        if presets.contains(duration) {
            selectedPresetSeconds = duration
        }
        // Non-preset durations leave selection as-is without labeling "Active".
    }
}

#Preview("Pawel timer modal idle") {
    PawelTimerModal(controller: TrainBootstrap.sessionController)
        .helmTheme()
}
