import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private enum LiveActivityMetrics {
    static let sectionSpacing: CGFloat = 8
    static let verticalPadding: CGFloat = 12
    static let horizontalPadding: CGFloat = 16
    static let doneMinWidth: CGFloat = 72
    /// Signal-blue surround (matches brand accent used in Signal skin).
    static let signalBlue = Color(red: 0.16, green: 0.55, blue: 1.0)
    /// Upper bound for count-up elapsed `timerInterval` (system-rendered, no 1Hz updates).
    static let elapsedWindow: TimeInterval = 60 * 60 * 12
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
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        if let exercise = context.state.currentExerciseName {
                            Text(exercise)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        elapsedTimerLabel(startedAt: context.attributes.startedAt)
                            .font(.caption.monospacedDigit().weight(.semibold))
                        restOrHeartTrailing(context.state)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        setProgressLabel(context.state)
                        Spacer(minLength: 8)
                        if let target = context.state.targetSummary, !target.isEmpty {
                            Text(target)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        doneButton(for: context.state)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(LiveActivityMetrics.signalBlue)
            } compactTrailing: {
                compactRestOrElapsed(
                    state: context.state,
                    startedAt: context.attributes.startedAt
                )
            } minimal: {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(LiveActivityMetrics.signalBlue)
            }
            .keylineTint(LiveActivityMetrics.signalBlue)
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<WorkoutActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: LiveActivityMetrics.sectionSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(context.attributes.sessionTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                elapsedTimerLabel(startedAt: context.attributes.startedAt)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }

            if let exercise = context.state.currentExerciseName {
                Text(exercise)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    setProgressLabel(context.state)
                        .foregroundStyle(.white.opacity(0.9))
                    if let target = context.state.targetSummary, !target.isEmpty {
                        Text(target)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    restCountdownLabel(context.state)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(LiveActivityMetrics.signalBlue)
                    if !context.state.isResting, let bpm = context.state.heartRateBPM {
                        Label("\(bpm) BPM", systemImage: "heart.fill")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.pink)
                    }
                }
                Spacer(minLength: 8)
                doneButton(for: context.state)
            }
        }
        .padding(.horizontal, LiveActivityMetrics.horizontalPadding)
        .padding(.vertical, LiveActivityMetrics.verticalPadding)
        .activityBackgroundTint(Color.black)
        .activitySystemActionForegroundColor(.white)
    }

    @ViewBuilder
    private func restOrHeartTrailing(_ state: WorkoutActivityAttributes.ContentState) -> some View {
        if state.isResting {
            restCountdownLabel(state)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(LiveActivityMetrics.signalBlue)
        } else if let bpm = state.heartRateBPM {
            Text("\(bpm) BPM")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func compactRestOrElapsed(
        state: WorkoutActivityAttributes.ContentState,
        startedAt: Date
    ) -> some View {
        if state.isResting {
            restCountdownLabel(state)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(LiveActivityMetrics.signalBlue)
        } else {
            elapsedTimerLabel(startedAt: startedAt)
                .font(.caption2.monospacedDigit())
        }
    }

    /// System-rendered count-up from session start - stays accurate while app is suspended.
    private func elapsedTimerLabel(startedAt: Date) -> Text {
        Text(
            timerInterval: startedAt ... startedAt.addingTimeInterval(LiveActivityMetrics.elapsedWindow),
            countsDown: false
        )
    }

    @ViewBuilder
    private func restCountdownLabel(_ state: WorkoutActivityAttributes.ContentState) -> some View {
        if let endsAt = state.restEndsAt, endsAt > Date() {
            Text(timerInterval: Date.now ... endsAt, countsDown: true)
        } else if let rest = state.restRemainingSeconds, rest > 0 {
            Text("Rest \(restLabel(rest))")
        }
    }

    @ViewBuilder
    private func setProgressLabel(_ state: WorkoutActivityAttributes.ContentState) -> some View {
        if let number = state.currentSetNumber, let count = state.currentSetCount {
            Text("Set \(number) of \(count)")
                .font(.caption.weight(.semibold))
        }
    }

    @ViewBuilder
    private func doneButton(for state: WorkoutActivityAttributes.ContentState) -> some View {
        if let exerciseID = state.sessionExerciseID,
           let setID = state.currentSetID,
           !state.isResting {
            Button(
                intent: CompleteLiveActivitySetIntent(
                    sessionExerciseID: exerciseID,
                    setID: setID
                )
            ) {
                Text("Done")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(minWidth: LiveActivityMetrics.doneMinWidth)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.white, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func restLabel(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
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
#endif
