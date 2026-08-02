import Core
import DesignSystem
import SwiftUI

struct TrainSessionHeaderView: View {
    let startedAt: Date
    let progress: TrainSessionProgress
    var heartRateBPM: Int?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = max(0, Int(context.date.timeIntervalSince(startedAt)))
            HStack(spacing: HelmSpacing.sm) {
                if let heartRateBPM {
                    HStack(spacing: HelmSpacing.xxs) {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(HelmColor.destructive)
                        Text("\(heartRateBPM)")
                            .helmType(.monoTag, color: HelmColor.fg)
                            .monospacedDigit()
                    }
                }

                Text(TrainSessionProgressFormatter.elapsedLabel(seconds: elapsed))
                    .helmType(.label, color: HelmColor.textPrimary)
                    .monospacedDigit()

                Text("·")
                    .helmType(.monoTag, color: HelmColor.fgMuted)

                Text(TrainSessionProgressFormatter.setCountLabel(
                    completed: progress.completedSetCount,
                    total: progress.totalSetCount
                ))
                .helmType(.monoTag, color: HelmColor.fgSecondary)
                .monospacedDigit()

                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel(elapsed: elapsed))
        }
    }

    private func accessibilityLabel(elapsed: Int) -> String {
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        var parts: [String] = []
        if let heartRateBPM {
            parts.append("\(heartRateBPM) beats per minute")
        }
        parts.append("Elapsed \(minutes) minutes \(seconds) seconds")
        parts.append("\(progress.completedSetCount) of \(progress.totalSetCount) sets completed")
        return parts.joined(separator: ". ")
    }
}

#Preview("Train session header") {
    TrainSessionHeaderView(
        startedAt: Date().addingTimeInterval(-754),
        progress: TrainSessionProgress(elapsedSeconds: 754, completedSetCount: 2, totalSetCount: 5),
        heartRateBPM: 142
    )
    .padding()
    .helmTheme()
}
