import Core
import DesignSystem
import SwiftUI

struct PawelTimerModal: View {
    @Bindable var controller: TrainSessionController

    @State private var selectedPresetSeconds = 90
    @State private var isMutating = false
    @State private var sheetDetent: PresentationDetent = .medium

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
            ScrollView {
                VStack(spacing: HelmSpacing.lg) {
                    timerRingSection
                    if isRunning {
                        restAdjustButtons
                    }
                    primaryActionButton
                    presetGrid
                }
                .padding(HelmSpacing.md)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .helmScreenBackground()
            .navigationTitle("Timer")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isMutating)
            .onAppear {
                syncSelectedPresetFromRunningTimer()
                sheetDetent = controller.pawelTimerOpenExpanded ? .large : .medium
            }
            .onChange(of: restTimer?.id) { _, _ in
                syncSelectedPresetFromRunningTimer()
            }
            .onChange(of: restTimer?.defaultDurationSeconds) { _, _ in
                syncSelectedPresetFromRunningTimer()
            }
        }
        .presentationDetents([.medium, .large], selection: $sheetDetent)
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var timerRingSection: some View {
        if isRunning, let timer = restTimer {
            let totalSeconds = controller.restTimerTotalSeconds(for: timer)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = controller.localRemainingRestSeconds(at: context.date)
                    ?? timer.remainingSeconds(at: context.date)
                    ?? selectedPresetSeconds
                let fraction = RestTimerBannerProgress.remainingFraction(
                    remainingSeconds: remaining,
                    totalSeconds: totalSeconds
                )
                RadialCountdownRing(
                    remainingSeconds: remaining,
                    remainingFraction: fraction
                )
                .frame(maxWidth: 280)
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

    private var restAdjustButtons: some View {
        HStack(spacing: HelmSpacing.sm) {
            Button {
                runMutation { await controller.adjustRestTimer(deltaSeconds: -15) }
            } label: {
                Text("−15")
            }
            .buttonStyle(RestDockChipStyle())
            .disabled(isMutating)
            .accessibilityLabel("Subtract 15 seconds")

            Button {
                runMutation { await controller.adjustRestTimer(deltaSeconds: 15) }
            } label: {
                Text("+15")
            }
            .buttonStyle(RestDockChipStyle())
            .disabled(isMutating)
            .accessibilityLabel("Add 15 seconds")
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
        Task { @MainActor in
            await work()
            // Persistence awaits can resume a `@MainActor` task off the real main thread.
            // Hop via DispatchQueue.main before touching SwiftUI `@State`.
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.async {
                    isMutating = false
                    continuation.resume()
                }
            }
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
