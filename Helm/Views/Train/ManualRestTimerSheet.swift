import Core
import DesignSystem
import SwiftUI

struct ManualRestTimerSheet: View {
    @Bindable var controller: TrainSessionController
    @Bindable private var trainPreferences = TrainPreferences.shared

    @State private var selectedSeconds = TrainPreferencePersistence.ManualRestTimerDuration.defaultSeconds
    @State private var isCustomMode = false
    @State private var isMutating = false
    @State private var sheetDetent: PresentationDetent = .large

    private let presets = TrainPreferencePersistence.ManualRestTimerDuration.presets

    private var isRunning: Bool {
        controller.isRestTimerRunning
    }

    private var restTimer: RestTimer? {
        controller.snapshot?.restTimer
    }

    var body: some View {
        NavigationStack {
            Group {
                if isRunning {
                    activeContent
                } else {
                    idleContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .helmScreenBackground()
            .navigationTitle("Manual rest timer")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isMutating)
            .animation(HelmMotion.standardAnimation, value: isRunning)
            .animation(HelmMotion.quickAnimation, value: isCustomMode)
            .onAppear {
                restoreSelection()
                sheetDetent = .medium
                if !isRunning {
                    sheetDetent = .large
                }
            }
            .onChange(of: isRunning) { _, running in
                sheetDetent = running ? .medium : .large
            }
            .onChange(of: restTimer?.id) { _, _ in
                syncFromRunningTimer()
            }
            .onChange(of: restTimer?.defaultDurationSeconds) { _, _ in
                syncFromRunningTimer()
            }
        }
        .presentationDetents(isRunning ? [.medium, .large] : [.large, .medium], selection: $sheetDetent)
        .presentationDragIndicator(.visible)
    }

    private var idleContent: some View {
        ScrollView {
            VStack(spacing: HelmSpacing.lg) {
                RadialCountdownRing(
                    remainingSeconds: selectedSeconds,
                    remainingFraction: 1
                )
                .frame(maxWidth: 260)
                .padding(HelmSpacing.md)
                .helmPanelChrome(.accentQuiet, cornerRadius: HelmRadius.lg)
                .padding(.top, HelmSpacing.sm)

                presetRow

                if isCustomMode {
                    HelmDurationWheelPicker(value: $selectedSeconds)
                        .clipShape(RoundedRectangle(cornerRadius: HelmRadius.md))
                        .overlay {
                            RoundedRectangle(cornerRadius: HelmRadius.md)
                                .strokeBorder(HelmColor.hairline, lineWidth: 1)
                        }
                        .onChange(of: selectedSeconds) { _, newValue in
                            trainPreferences.manualRestTimerDurationSeconds = newValue
                        }
                }

                Button {
                    runMutation {
                        trainPreferences.manualRestTimerDurationSeconds = selectedSeconds
                        await controller.startManualRest(durationSeconds: selectedSeconds)
                    }
                } label: {
                    Text("Start")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                }
                .buttonStyle(.helmPrimary)
                .disabled(isMutating)
                .accessibilityLabel("Start timer")
            }
            .padding(HelmSpacing.md)
        }
    }

    private var activeContent: some View {
        VStack(spacing: HelmSpacing.lg) {
            Spacer(minLength: HelmSpacing.sm)

            if let timer = restTimer {
                let totalSeconds = controller.restTimerTotalSeconds(for: timer)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = controller.localRemainingRestSeconds(at: context.date)
                        ?? timer.remainingSeconds(at: context.date)
                        ?? selectedSeconds
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
            }

            HStack(spacing: HelmSpacing.md) {
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
            .padding(.horizontal, HelmSpacing.sm)

            Button {
                runMutation { await controller.skipRest() }
            } label: {
                Text("Stop")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
            }
            .buttonStyle(.helmPrimary)
            .disabled(isMutating)
            .accessibilityLabel("Stop timer")

            Spacer(minLength: HelmSpacing.md)
        }
        .padding(HelmSpacing.md)
    }

    private var presetRow: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text("DURATION")
                .helmType(.monoTag, color: HelmColor.fgMuted)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: HelmSpacing.sm
            ) {
                ForEach(presets, id: \.self) { seconds in
                    presetChip(
                        title: "\(seconds)s",
                        isSelected: !isCustomMode && selectedSeconds == seconds
                    ) {
                        isCustomMode = false
                        selectedSeconds = seconds
                        trainPreferences.manualRestTimerDurationSeconds = seconds
                        HapticEngine.shared.play(.selection)
                    }
                    .accessibilityLabel("\(seconds) seconds")
                }
            }

            presetChip(
                title: "Custom",
                isSelected: isCustomMode
            ) {
                isCustomMode = true
                selectedSeconds = TrainPreferencePersistence.ManualRestTimerDuration.snapped(
                    selectedSeconds
                )
                trainPreferences.manualRestTimerDurationSeconds = selectedSeconds
                HapticEngine.shared.play(.selection)
            }
            .accessibilityLabel("Custom duration")
        }
    }

    private func presetChip(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .helmType(.label, color: isSelected ? HelmColor.accent : HelmColor.fg)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(
                    isSelected ? HelmColor.accent.opacity(0.12) : HelmColor.surfaceElevated,
                    in: RoundedRectangle(cornerRadius: HelmRadius.md)
                )
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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func restoreSelection() {
        let stored = trainPreferences.manualRestTimerDurationSeconds
        selectedSeconds = stored
        isCustomMode = !presets.contains(stored)
        syncFromRunningTimer()
    }

    private func syncFromRunningTimer() {
        guard let timer = restTimer, isRunning else { return }
        let duration = timer.defaultDurationSeconds
        selectedSeconds = TrainPreferencePersistence.ManualRestTimerDuration.snapped(duration)
        isCustomMode = !presets.contains(selectedSeconds)
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
}

#Preview("Manual rest timer sheet idle") {
    ManualRestTimerSheet(controller: TrainBootstrap.sessionController)
        .helmTheme()
}
