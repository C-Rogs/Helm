import Core
import DesignSystem
import SwiftUI

struct TrainSessionHeaderView: View {
    let startedAt: Date
    let progress: TrainSessionProgress

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = max(0, Int(context.date.timeIntervalSince(startedAt)))
            VStack(spacing: HelmSpacing.xxs) {
                Text("Train")
                    .helmType(.label, color: HelmColor.textPrimary)

                HStack(spacing: HelmSpacing.xs) {
                    Text(TrainSessionProgressFormatter.elapsedLabel(seconds: elapsed))
                    Text("·")
                    Text(TrainSessionProgressFormatter.setCountLabel(
                        completed: progress.completedSetCount,
                        total: progress.totalSetCount
                    ))
                }
                .helmType(.monoTag, color: HelmColor.fgSecondary)
                .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel(elapsed: elapsed))
        }
    }

    private func accessibilityLabel(elapsed: Int) -> String {
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return "Train. Elapsed \(minutes) minutes \(seconds) seconds. \(progress.completedSetCount) of \(progress.totalSetCount) sets completed."
    }
}

#Preview("Train session header") {
    TrainSessionHeaderView(
        startedAt: Date().addingTimeInterval(-754),
        progress: TrainSessionProgress(elapsedSeconds: 754, completedSetCount: 2, totalSetCount: 5)
    )
    .helmTheme()
}
