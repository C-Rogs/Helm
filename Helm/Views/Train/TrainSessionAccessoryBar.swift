import ActivityKit
import Core
import DesignSystem
import SwiftUI
import UIKit

/// Rest + Ask coach chrome pinned to the bottom of Train content.
/// Kept out of `tabViewBottomAccessory`: iOS 26 reserves a tall empty slot there.
struct TrainSessionAccessoryBar: View {
    @Bindable private var controller = TrainBootstrap.sessionController
    @Bindable private var trainPreferences = TrainPreferences.shared
    @State private var didTrackInitialRestRemaining = false

    static func isEnabled(
        selectedTab: AppTab,
        controller: TrainSessionController,
        cardLoggingModeEnabled: Bool
    ) -> Bool {
        guard selectedTab == .train, controller.hasActiveSession, controller.numpadTarget == nil else {
            return false
        }
        let showRest = controller.isRestTimerRunning
            && controller.snapshot?.restTimer?.endsAt != nil
        let showCoach = !controller.isReorderMode && !cardLoggingModeEnabled
        return showRest || showCoach
    }

    var body: some View {
        let showRest = controller.isRestTimerRunning
            && controller.snapshot?.restTimer?.endsAt != nil
        let showCoach = !controller.isReorderMode
            && !trainPreferences.cardLoggingModeEnabled

        VStack(spacing: HelmSpacing.xs) {
            if showRest,
               let timer = controller.snapshot?.restTimer,
               let endsAt = timer.endsAt {
                RestTimerBanner(
                    endsAt: endsAt,
                    totalSeconds: controller.restTimerTotalSeconds(for: timer),
                    onSkip: {
                        Task { @MainActor in await controller.skipRest() }
                    },
                    onAdjust: { delta in
                        Task { @MainActor in await controller.adjustRestTimer(deltaSeconds: delta) }
                    },
                    onRemainingSecondsChange: forwardRestTick,
                    upNextName: controller.upNextExerciseName
                )
            }

            if showCoach {
                coachBar
            }
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, HelmSpacing.xxs)
    }

    private var coachBar: some View {
        let restTimer = controller.snapshot?.restTimer
        let bar = AskCoachBar(
            prompt: controller.isCoachThinking ? "Coach thinking" : "Ask coach",
            peekSnippet: ProactiveCoachPreferences.peekEnabled ? controller.coachPeekSnippet : nil,
            isLoading: controller.isCoachThinking
        ) {
            controller.isShowingCoachPrompt = true
        }

        return Group {
            if trainPreferences.manualRestTimerEnabled {
                HStack(spacing: HelmSpacing.xs) {
                    bar
                        .layoutPriority(1)

                    ManualRestTimerPill(
                        isRunning: controller.isRestTimerRunning,
                        endsAt: restTimer?.endsAt
                    ) {
                        controller.openManualRestTimer(expanded: controller.isRestTimerRunning)
                    }
                    .fixedSize()
                }
                .padding(.horizontal, HelmSpacing.screenGutter)
                .padding(.bottom, HelmSpacing.xs)
            } else {
                bar
                    .padding(.horizontal, HelmSpacing.screenGutter)
                    .padding(.bottom, HelmSpacing.xs)
            }
        }
    }

    private func forwardRestTick(_ remaining: Int) {
        if !didTrackInitialRestRemaining {
            didTrackInitialRestRemaining = true
            controller.handleRestRemainingSecondsChange(remaining > 0 ? remaining : 0)
            return
        }
        controller.handleRestRemainingSecondsChange(remaining)
    }
}

/// In-app stand-in for the workout Dynamic Island when the athlete is off Train.
struct InAppWorkoutIsland: View {
    @Bindable private var controller = TrainBootstrap.sessionController
    @Bindable private var tabRouter = AppTabRouter.shared
    @Environment(\.helmReduceMotion) private var reduceMotion
    @State private var isExpanded = false
    @State private var topSafeArea: CGFloat = IslandChrome.fallbackTopInset
    @State private var hasSystemLiveActivity = false

    var body: some View {
        if tabRouter.selectedTab != .train, let model = Self.model(from: controller) {
            Group {
                if isExpanded {
                    ZStack(alignment: .top) {
                        frostScrim
                        islandColumn(model)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea()
                } else if !hasSystemLiveActivity {
                    islandColumn(model)
                        .ignoresSafeArea(edges: .top)
                }
            }
            .allowsHitTesting(isExpanded || !hasSystemLiveActivity)
            .animation(HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: reduceMotion), value: isExpanded)
            .onChange(of: controller.hasActiveSession) { _, live in
                if !live { isExpanded = false }
            }
            .onChange(of: tabRouter.selectedTab) { _, tab in
                if tab == .train { isExpanded = false }
            }
            .onAppear {
                topSafeArea = Self.windowTopSafeArea()
            }
            .task(id: controller.hasActiveSession) {
                guard controller.hasActiveSession else {
                    hasSystemLiveActivity = false
                    return
                }
                for _ in 0 ..< 20 {
                    hasSystemLiveActivity = Self.isSystemLiveActivityRunning
                    if hasSystemLiveActivity || Task.isCancelled { return }
                    try? await Task.sleep(for: .milliseconds(250))
                }
                hasSystemLiveActivity = Self.isSystemLiveActivityRunning
            }
        }
    }

    private var islandPalette: HelmPalette { .dark }

    private func islandColumn(_ model: Model) -> some View {
        VStack(spacing: HelmSpacing.xs) {
            compact(model)
            if isExpanded {
                expanded(model)
                    .padding(.horizontal, HelmSpacing.md)
            }
        }
        .padding(.top, islandTopPadding)
    }

    private var frostScrim: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            HelmColor.canvas.opacity(0.78)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {
            HapticEngine.shared.play(.selection)
            isExpanded = false
        }
        .accessibilityLabel("Dismiss workout details")
        .accessibilityAddTraits(.isButton)
    }

    private func compact(_ model: Model) -> some View {
        let palette = islandPalette
        return Button {
            HapticEngine.shared.play(.selection)
            isExpanded.toggle()
        } label: {
            HStack(spacing: 0) {
                compactArc(isResting: model.isResting, palette: palette)
                    .frame(
                        width: IslandChrome.compactGlyphSize,
                        height: IslandChrome.compactGlyphSize
                    )
                    .frame(
                        width: IslandChrome.compactContentWidth,
                        height: IslandChrome.hardwareHeight,
                        alignment: .trailing
                    )
                    .padding(.leading, IslandChrome.compactSideInset)
                    .padding(.trailing, IslandChrome.compactIslandGap)

                Color.clear
                    .frame(width: IslandChrome.hardwareWidth, height: IslandChrome.hardwareHeight)
                    .accessibilityHidden(true)

                compactTrailing(model, palette: palette)
                    .frame(
                        width: IslandChrome.compactContentWidth,
                        height: IslandChrome.hardwareHeight,
                        alignment: .leading
                    )
                    .padding(.leading, IslandChrome.compactIslandGap)
                    .padding(.trailing, IslandChrome.compactSideInset)
            }
            .frame(width: IslandChrome.compactWidth, height: IslandChrome.hardwareHeight)
            .background(palette.canvas, in: Capsule())
            .contentShape(Capsule())
            .clipShape(Capsule())
        }
        .buttonStyle(IslandCompactButtonStyle())
        .dynamicTypeSize(.large)
        .accessibilityLabel(compactAccessibility(model))
        .accessibilityHint(isExpanded ? "Collapses workout controls" : "Shows workout controls")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func expanded(_ model: Model) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.sessionTitle)
                    .helmType(.label, color: HelmColor.fg)
                    .lineLimit(1)
                Spacer(minLength: HelmSpacing.xs)
                elapsedLabel(startedAt: model.startedAt)
                    .helmType(.number, color: HelmColor.fgSecondary)
            }

            if let exercise = model.exerciseName {
                Text(exercise)
                    .helmType(.body, color: HelmColor.fg)
                    .lineLimit(1)
            }

            HStack(alignment: .center, spacing: HelmSpacing.sm) {
                VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                    setLine(model)
                    if model.isResting {
                        restLabel(model)
                            .helmType(.bigNumber, color: HelmColor.accent)
                    } else {
                        heartRateRow(model)
                    }
                }
                Spacer(minLength: HelmSpacing.xs)
                expandedActions(model)
            }
        }
        .padding(HelmSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous)
                    .fill(HelmColor.surfaceElevated)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous)
                .strokeBorder(HelmColor.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func expandedActions(_ model: Model) -> some View {
        VStack(spacing: HelmSpacing.xs) {
            if !model.isResting, let exerciseID = model.sessionExerciseID, let setID = model.currentSetID {
                Button("Done") {
                    Task { @MainActor in
                        await controller.completeSetIfNeeded(sessionExerciseID: exerciseID, setID: setID)
                    }
                }
                .buttonStyle(.helmPrimary)
                .accessibilityLabel("Complete set")
            }

            Button("Train") {
                HapticEngine.shared.play(.selection)
                tabRouter.selectedTab = .train
            }
            .buttonStyle(.helmSecondary)
            .accessibilityLabel("Open Train")
        }
        .fixedSize()
    }

    private func compactTrailing(_ model: Model, palette: HelmPalette) -> some View {
        Group {
            if model.isResting {
                restLabel(model)
                    .foregroundStyle(palette.accent)
            } else {
                elapsedLabel(startedAt: model.startedAt)
                    .foregroundStyle(palette.fg)
            }
        }
        .font(.system(size: 13, weight: .semibold).monospacedDigit())
        .multilineTextAlignment(.leading)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(width: IslandChrome.compactContentWidth, alignment: .leading)
    }

    private func compactArc(isResting: Bool, palette: HelmPalette) -> some View {
        let color = isResting ? palette.accent : palette.fg
        return ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(palette.fg.opacity(0.22), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            Circle()
                .trim(from: 0, to: 0.75 * (isResting ? 1 : 0.67))
                .stroke(color, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        }
        .rotationEffect(.degrees(135))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func setLine(_ model: Model) -> some View {
        let tokens = WatchCompanionSetLine.tokens(
            setNumber: model.setNumber,
            setCount: model.setCount,
            targetSummary: model.targetSummary
        )
        if tokens.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 0) {
                ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                    Text(token.text)
                        .helmType(token.isValue ? .number : .body, color: token.isValue ? HelmColor.fg : HelmColor.fgSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityLabel(tokens.map(\.text).joined())
        }
    }

    @ViewBuilder
    private func heartRateRow(_ model: Model) -> some View {
        let bpm = model.heartRateBPM
        HStack(spacing: HelmSpacing.xxs) {
            Image(systemName: bpm == nil ? HelmIcon.heart.rawValue : "heart.fill")
                .font(.caption)
                .foregroundStyle(bpm == nil ? HelmColor.fgMuted : HelmColor.depleted)
            Text(bpm.map(String.init) ?? "--")
                .helmType(.number, color: bpm == nil ? HelmColor.fgMuted : HelmColor.fg)
            Text("BPM")
                .helmType(.monoTag, color: HelmColor.fgMuted)
        }
        .privacySensitive()
        .accessibilityLabel(bpm.map { "\($0) beats per minute" } ?? "Heart rate unavailable")
    }

    private func elapsedLabel(startedAt: Date) -> Text {
        Text(
            timerInterval: startedAt ... startedAt.addingTimeInterval(Self.elapsedWindow),
            countsDown: false
        )
    }

    @ViewBuilder
    private func restLabel(_ model: Model) -> some View {
        if let endsAt = model.restEndsAt, endsAt > Date() {
            Text(timerInterval: Date.now ... endsAt, countsDown: true)
        } else if let rest = model.restRemainingSeconds, rest > 0 {
            Text(String(format: "%d:%02d", rest / 60, rest % 60))
        }
    }

    private func compactAccessibility(_ model: Model) -> String {
        var parts = [model.sessionTitle]
        if model.isResting {
            parts.append("Resting")
        } else if let exercise = model.exerciseName {
            parts.append(exercise)
        }
        return parts.joined(separator: ", ")
    }

    private struct Model {
        let sessionTitle: String
        let startedAt: Date
        let exerciseName: String?
        let setNumber: Int?
        let setCount: Int?
        let targetSummary: String?
        let restRemainingSeconds: Int?
        let restEndsAt: Date?
        let heartRateBPM: Int?
        let sessionExerciseID: String?
        let currentSetID: String?

        var isResting: Bool {
            if let restEndsAt { return restEndsAt > Date() }
            return (restRemainingSeconds ?? 0) > 0
        }
    }

    private var islandTopPadding: CGFloat {
        max(0, (topSafeArea - IslandChrome.hardwareHeight) / 2)
    }

    private static func windowTopSafeArea() -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.first?.windows.first
        return window?.safeAreaInsets.top ?? IslandChrome.fallbackTopInset
    }

    private static var isSystemLiveActivityRunning: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
            && !Activity<WorkoutActivityAttributes>.activities.isEmpty
    }

    private enum IslandChrome {
        /// iPhone 14 Pro…17 Pro cutout. Measured 125.3×36 on iPhone 17 Pro @3x.
        static let hardwareWidth: CGFloat = 125
        static let hardwareHeight: CGFloat = 36
        static let compactGlyphSize: CGFloat = 20
        static let compactContentWidth: CGFloat = 38
        static let compactSideInset: CGFloat = 8
        static let compactIslandGap: CGFloat = 6
        static let fallbackTopInset: CGFloat = 62

        static var compactSlotWidth: CGFloat {
            compactSideInset + compactContentWidth + compactIslandGap
        }

        static var compactWidth: CGFloat {
            hardwareWidth + compactSlotWidth * 2
        }
    }

    private struct IslandCompactButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.88 : 1)
        }
    }

    private static let elapsedWindow: TimeInterval = 60 * 60 * 12

    private static func model(from controller: TrainSessionController) -> Model? {
        guard let snapshot = controller.snapshot else { return nil }
        let currentExercise = snapshot.session.exercises.first { exercise in
            exercise.sets.contains { $0.status != .completed }
        } ?? snapshot.session.exercises.first
        let currentSet = currentExercise?.sets.first { $0.status != .completed }
        let setNumber = currentExercise.flatMap { exercise in
            exercise.sets.firstIndex { $0.status != .completed }.map { $0 + 1 }
        }
        let restEndsAt: Date? = {
            guard let timer = snapshot.restTimer, timer.phase == .running else { return nil }
            return timer.endsAt
        }()
        return Model(
            sessionTitle: {
                let trimmed = snapshot.session.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let trimmed, !trimmed.isEmpty { return trimmed }
                return "Train"
            }(),
            startedAt: snapshot.session.startedAt,
            exerciseName: currentExercise.flatMap { controller.exerciseSummaries[$0.exerciseID]?.displayName },
            setNumber: setNumber,
            setCount: currentExercise?.sets.count,
            targetSummary: currentExercise.flatMap { controller.exerciseTargets[$0.exerciseID] },
            restRemainingSeconds: controller.localRemainingRestSeconds(),
            restEndsAt: restEndsAt,
            heartRateBPM: WatchReadinessBootstrap.coordinator.liveHeartRateBPMForDisplay,
            sessionExerciseID: currentExercise?.id,
            currentSetID: currentSet?.id
        )
    }
}
