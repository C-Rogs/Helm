import ActivityKit
import SwiftUI
import WidgetKit

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(context.attributes.sessionTitle)
                        .font(.headline)
                    Spacer()
                    Text(elapsedLabel(context.state.elapsedSeconds))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if let exercise = context.state.currentExerciseName {
                    Text(exercise)
                        .font(.subheadline)
                }

                if let rest = context.state.restRemainingSeconds, rest > 0 {
                    Label("Rest \(rest)s", systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 4)
            .activityBackgroundTint(.black.opacity(0.85))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.sessionTitle)
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(elapsedLabel(context.state.elapsedSeconds))
                        .font(.caption.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let exercise = context.state.currentExerciseName {
                        Text(exercise)
                            .font(.caption2)
                    }
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
            } compactTrailing: {
                if let rest = context.state.restRemainingSeconds, rest > 0 {
                    Text("\(rest)s")
                        .font(.caption2.monospacedDigit())
                } else {
                    Text(elapsedLabel(context.state.elapsedSeconds))
                        .font(.caption2.monospacedDigit())
                }
            } minimal: {
                Image(systemName: "dumbbell.fill")
            }
        }
    }

    private func elapsedLabel(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }
}
