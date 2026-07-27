import ActivityKit
import SwiftUI
import WidgetKit

private enum LiveActivityMetrics {
    static let sectionSpacing: CGFloat = 10
    static let verticalPadding: CGFloat = 8
    static let horizontalPadding: CGFloat = 14
}

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: LiveActivityMetrics.sectionSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text(context.attributes.sessionTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(elapsedLabel(context.state.elapsedSeconds))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if let exercise = context.state.currentExerciseName {
                    Text(exercise)
                        .font(.subheadline)
                        .lineLimit(1)
                }

                if let rest = context.state.restRemainingSeconds, rest > 0 {
                    Label("Rest \(restLabel(rest))", systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, LiveActivityMetrics.horizontalPadding)
            .padding(.vertical, LiveActivityMetrics.verticalPadding)
            .activityBackgroundTint(.black.opacity(0.85))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.sessionTitle)
                        .font(.caption)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(elapsedLabel(context.state.elapsedSeconds))
                        .font(.caption.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let exercise = context.state.currentExerciseName {
                        Text(exercise)
                            .font(.caption2)
                            .lineLimit(1)
                            .padding(.top, 4)
                    }
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
            } compactTrailing: {
                if let rest = context.state.restRemainingSeconds, rest > 0 {
                    Text(restLabel(rest))
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

    private func restLabel(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }
}
