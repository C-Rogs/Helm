import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Dark-profile instrument tokens. Widget extension cannot load DesignSystem; hex matches DESIGN-SYSTEM.md.
private enum WidgetPalette {
    static let canvas = Color(hex: 0x000000)
    static let fg = Color(hex: 0xF4F3EE)
    static let fgSecondary = Color(hex: 0xA8A7A0)
    static let fgMuted = Color(hex: 0x6B6A63)
    static let hairline = Color.white.opacity(0.09)
    static let accent = Color(hex: 0xC6F24E)
    static let depleted = Color(hex: 0xFF6A4D)
    static let buttonPrimaryForeground = Color.black
}

private enum WidgetType {
    static let heroRest: Font = .system(size: 22, weight: .bold).monospacedDigit()
    static let number: Font = .system(size: 16, weight: .semibold).monospacedDigit()
    static let compactNumber: Font = .system(size: 13, weight: .semibold).monospacedDigit()
    static let title: Font = .system(size: 17, weight: .semibold)
    static let body: Font = .system(size: 13.5, weight: .regular)
    static let caption: Font = .system(size: 12, weight: .regular)
    static let captionSemibold: Font = .system(size: 12, weight: .semibold)
    static let monoTag: Font = .system(size: 10, weight: .medium, design: .monospaced)
    static let monoTagTracking: CGFloat = 1.4
}

/// 270-degree Arc marque (DESIGN-SYSTEM §3). Stroke scales with radius, capped for Island / lock screen.
private struct WidgetArc: View {
    var progress: Double
    var color: Color
    var track: Color = WidgetPalette.hairline
    var lineWidth: CGFloat? = nil

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let stroke = lineWidth ?? min(side * 0.12, 4)
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(track, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                Circle()
                    .trim(from: 0, to: 0.75 * max(0, min(1, progress)))
                    .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            }
            .rotationEffect(.degrees(135))
            .frame(width: side - stroke, height: side - stroke)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private enum LiveActivityMetrics {
    static let sectionSpacing: CGFloat = 8
    static let verticalPadding: CGFloat = 12
    static let horizontalPadding: CGFloat = 16
    static let doneMinWidth: CGFloat = 72
    static let compactGlyphSize: CGFloat = 20
    /// Upper bound for count-up elapsed `timerInterval` (system-rendered, no 1Hz updates).
    static let elapsedWindow: TimeInterval = 60 * 60 * 12
    /// `Text(timerInterval:)` otherwise reserves room for the widest value in the range,
    /// which stretches the compact pill. Pin it to digit-clock width instead.
    static let compactTimerWidth: CGFloat = 46
}

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.sessionTitle)
                            .font(WidgetType.captionSemibold)
                            .foregroundStyle(WidgetPalette.fg)
                            .lineLimit(1)
                        if let exercise = context.state.currentExerciseName {
                            Text(exercise)
                                .font(WidgetType.caption)
                                .foregroundStyle(WidgetPalette.fgSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        elapsedTimerLabel(startedAt: context.attributes.startedAt)
                            .font(WidgetType.compactNumber)
                            .foregroundStyle(WidgetPalette.fgSecondary)
                        restOrHeartTrailing(context.state)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .center, spacing: 8) {
                        setProgressLabel(context.state)
                        if let target = context.state.targetSummary, !target.isEmpty {
                            Text("·")
                                .font(WidgetType.monoTag)
                                .foregroundStyle(WidgetPalette.fgMuted)
                            Text(target)
                                .font(WidgetType.compactNumber)
                                .foregroundStyle(WidgetPalette.fgSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        doneControl(for: context.state)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                WidgetArc(
                    progress: 1,
                    color: context.state.isResting ? WidgetPalette.accent : WidgetPalette.fg
                )
                .frame(width: LiveActivityMetrics.compactGlyphSize, height: LiveActivityMetrics.compactGlyphSize)
            } compactTrailing: {
                compactRestOrElapsed(
                    state: context.state,
                    startedAt: context.attributes.startedAt
                )
            } minimal: {
                WidgetArc(
                    progress: context.state.isResting ? 1 : 0.67,
                    color: context.state.isResting ? WidgetPalette.accent : WidgetPalette.fg
                )
                .frame(width: 16, height: 16)
            }
            .keylineTint(WidgetPalette.accent)
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: LiveActivityMetrics.sectionSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(context.attributes.sessionTitle)
                    .font(WidgetType.title)
                    .foregroundStyle(WidgetPalette.fg)
                    .lineLimit(1)
                Spacer(minLength: 8)
                elapsedTimerLabel(startedAt: context.attributes.startedAt)
                    .font(WidgetType.number)
                    .foregroundStyle(WidgetPalette.fgSecondary)
            }

            if let exercise = context.state.currentExerciseName {
                Text(exercise)
                    .font(WidgetType.body)
                    .foregroundStyle(WidgetPalette.fg)
                    .lineLimit(1)
            }

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        setProgressLabel(context.state)
                        if let target = context.state.targetSummary, !target.isEmpty {
                            Text("·")
                                .font(WidgetType.monoTag)
                                .foregroundStyle(WidgetPalette.fgMuted)
                            Text(target)
                                .font(WidgetType.number)
                                .foregroundStyle(WidgetPalette.fgSecondary)
                                .lineLimit(1)
                        }
                    }
                    if context.state.isResting {
                        restRow(context.state)
                    } else {
                        heartRateReadout(context.state, compact: false)
                    }
                }
                Spacer(minLength: 8)
                doneControl(for: context.state)
            }
        }
        .padding(.horizontal, LiveActivityMetrics.horizontalPadding)
        .padding(.vertical, LiveActivityMetrics.verticalPadding)
        .activityBackgroundTint(WidgetPalette.canvas)
        .activitySystemActionForegroundColor(WidgetPalette.fg)
    }

    @ViewBuilder
    private func restOrHeartTrailing(_ state: WorkoutActivityAttributes.ContentState) -> some View {
        if state.isResting {
            restCountdownLabel(state)
                .font(WidgetType.compactNumber)
                .foregroundStyle(WidgetPalette.accent)
        } else {
            heartRateReadout(state, compact: true)
        }
    }

    @ViewBuilder
    private func compactRestOrElapsed(
        state: WorkoutActivityAttributes.ContentState,
        startedAt: Date
    ) -> some View {
        Group {
            if state.isResting {
                restCountdownLabel(state)
                    .foregroundStyle(WidgetPalette.accent)
            } else {
                elapsedTimerLabel(startedAt: startedAt)
                    .foregroundStyle(WidgetPalette.fg)
            }
        }
        .font(WidgetType.compactNumber)
        .multilineTextAlignment(.trailing)
        .minimumScaleFactor(0.7)
        .lineLimit(1)
        .frame(width: LiveActivityMetrics.compactTimerWidth, alignment: .trailing)
    }

    /// System-rendered count-up from session start - stays accurate while app is suspended.
    private func elapsedTimerLabel(startedAt: Date) -> Text {
        Text(
            timerInterval: startedAt ... startedAt.addingTimeInterval(LiveActivityMetrics.elapsedWindow),
            countsDown: false
        )
    }

    @ViewBuilder
    private func restRow(_ state: WorkoutActivityAttributes.ContentState) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            monoTag("REST")
                .accessibilityHidden(true)
            restCountdownLabel(state)
                .font(WidgetType.heroRest)
                .foregroundStyle(WidgetPalette.accent)
        }
    }

    @ViewBuilder
    private func restCountdownLabel(_ state: WorkoutActivityAttributes.ContentState) -> some View {
        if let endsAt = state.restEndsAt, endsAt > Date() {
            Text(timerInterval: Date.now ... endsAt, countsDown: true)
        } else if let rest = state.restRemainingSeconds, rest > 0 {
            Text(Self.mmss(rest))
        }
    }

    @ViewBuilder
    private func setProgressLabel(_ state: WorkoutActivityAttributes.ContentState) -> some View {
        if let number = state.currentSetNumber, let count = state.currentSetCount {
            HStack(spacing: 4) {
                monoTag("SET")
                Text("\(number)/\(count)")
                    .font(WidgetType.number)
                    .foregroundStyle(WidgetPalette.fg)
            }
            .accessibilityLabel("Set \(number) of \(count)")
        }
    }

    @ViewBuilder
    private func heartRateReadout(
        _ state: WorkoutActivityAttributes.ContentState,
        compact: Bool
    ) -> some View {
        let bpm = state.heartRateBPM
        HStack(spacing: 4) {
            Image(systemName: bpm == nil ? "heart" : "heart.fill")
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(bpm == nil ? WidgetPalette.fgMuted : WidgetPalette.depleted)
            Text(bpm.map(String.init) ?? "--")
                .font(compact ? WidgetType.compactNumber : WidgetType.number)
                .foregroundStyle(bpm == nil ? WidgetPalette.fgMuted : WidgetPalette.fg)
            if !compact {
                monoTag("BPM")
            }
        }
        .privacySensitive()
        .accessibilityLabel(bpm.map { "\($0) beats per minute" } ?? "Heart rate unavailable")
    }

    @ViewBuilder
    private func doneControl(for state: WorkoutActivityAttributes.ContentState) -> some View {
        if state.isResting {
            EmptyView()
        } else if let exerciseID = state.sessionExerciseID,
                  let setID = state.currentSetID {
            Button(
                intent: CompleteLiveActivitySetIntent(
                    sessionExerciseID: exerciseID,
                    setID: setID
                )
            ) {
                Text("Done")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WidgetPalette.buttonPrimaryForeground)
                    .frame(minWidth: LiveActivityMetrics.doneMinWidth)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        WidgetPalette.accent,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete set")
        } else {
            Text("DONE")
                .font(WidgetType.monoTag)
                .tracking(WidgetType.monoTagTracking)
                .foregroundStyle(WidgetPalette.fgMuted)
                .frame(minWidth: LiveActivityMetrics.doneMinWidth)
                .padding(.vertical, 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(WidgetPalette.hairline, lineWidth: 1)
                )
                .accessibilityLabel("Done unavailable")
        }
    }

    private func monoTag(_ text: String) -> some View {
        Text(text)
            .font(WidgetType.monoTag)
            .tracking(WidgetType.monoTagTracking)
            .textCase(.uppercase)
            .foregroundStyle(WidgetPalette.fgMuted)
    }

    private static func mmss(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }
}

private extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

#if DEBUG
#Preview("LA working", as: .content, using: WorkoutActivityAttributes(
    sessionTitle: "Push",
    startedAt: Date().addingTimeInterval(-1020)
)) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutActivityAttributes.ContentState(
        elapsedSeconds: 1020,
        currentExerciseName: "Bench Press (Barbell)",
        currentSetNumber: 3,
        currentSetCount: 5,
        targetSummary: "90 kg × 5",
        restRemainingSeconds: nil,
        restEndsAt: nil,
        heartRateBPM: 128,
        sessionExerciseID: "ex-1",
        currentSetID: "set-3"
    )
}

#Preview("LA resting", as: .content, using: WorkoutActivityAttributes(
    sessionTitle: "Push",
    startedAt: Date().addingTimeInterval(-1100)
)) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutActivityAttributes.ContentState(
        elapsedSeconds: 1100,
        currentExerciseName: "Bench Press (Barbell)",
        currentSetNumber: 4,
        currentSetCount: 5,
        targetSummary: "90 kg × 3",
        restRemainingSeconds: 95,
        restEndsAt: Date().addingTimeInterval(95),
        heartRateBPM: 118,
        sessionExerciseID: "ex-1",
        currentSetID: "set-4"
    )
}

#Preview("LA empty HR", as: .content, using: WorkoutActivityAttributes(
    sessionTitle: "Push",
    startedAt: Date().addingTimeInterval(-180)
)) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutActivityAttributes.ContentState(
        elapsedSeconds: 180,
        currentExerciseName: "Overhead Press (Barbell)",
        currentSetNumber: 1,
        currentSetCount: 4,
        targetSummary: "50 kg × 5",
        restRemainingSeconds: nil,
        restEndsAt: nil,
        heartRateBPM: nil,
        sessionExerciseID: nil,
        currentSetID: nil
    )
}
#endif
