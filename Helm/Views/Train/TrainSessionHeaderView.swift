import Core
import DesignSystem
import SwiftUI

struct TrainSessionHeaderView: View {
    let startedAt: Date
    let progress: TrainSessionProgress
    var watchLinkStatus: WatchCompanionLinkStatus = .unavailable

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = max(0, Int(context.date.timeIntervalSince(startedAt)))
            HStack(spacing: HelmSpacing.sm) {
                watchLinkChrome

                Text(TrainSessionProgressFormatter.elapsedLabel(seconds: elapsed))
                    .helmType(.label, color: HelmColor.textPrimary)
                    .helmNumericRoll(value: elapsed)

                Text("·")
                    .helmType(.monoTag, color: HelmColor.fgMuted)

                Text(TrainSessionProgressFormatter.setCountLabel(
                    completed: progress.completedSetCount,
                    total: progress.totalSetCount
                ))
                .helmType(.monoTag, color: HelmColor.fgSecondary)
                .helmNumericRoll(value: progress.completedSetCount)

                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel(elapsed: elapsed))
        }
    }

    @ViewBuilder
    private var watchLinkChrome: some View {
        switch watchLinkStatus {
        case .unavailable:
            EmptyView()
        case .connecting(.watch):
            HStack(spacing: HelmSpacing.xxs) {
                Image(systemName: "applewatch")
                    .font(.caption2)
                    .foregroundStyle(HelmColor.fgMuted)
                Text("Raise wrist for HR")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
            }
        case .connecting(.phone):
            HStack(spacing: HelmSpacing.xxs) {
                Image(systemName: "heart")
                    .font(.caption2)
                    .foregroundStyle(HelmColor.fgMuted)
                Text("Waiting for HR")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
            }
        case let .live(bpm):
            HStack(spacing: HelmSpacing.xxs) {
                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(HelmColor.destructive)
                HelmNumericText(bpm)
                    .helmType(.monoTag, color: HelmColor.fg)
            }
        }
    }

    private func accessibilityLabel(elapsed: Int) -> String {
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        var parts: [String] = []
        switch watchLinkStatus {
        case .unavailable:
            break
        case .connecting(.watch):
            parts.append("Waiting for Apple Watch heart rate. Raise wrist or open Watch app")
        case .connecting(.phone):
            parts.append("Waiting for heart rate from AirPods or another sensor")
        case let .live(bpm):
            parts.append("\(bpm) beats per minute")
        }
        parts.append("Elapsed \(minutes) minutes \(seconds) seconds")
        parts.append("\(progress.completedSetCount) of \(progress.totalSetCount) sets completed")
        return parts.joined(separator: ". ")
    }
}

#Preview("Train session header live") {
    TrainSessionHeaderView(
        startedAt: Date().addingTimeInterval(-754),
        progress: TrainSessionProgress(elapsedSeconds: 754, completedSetCount: 2, totalSetCount: 5),
        watchLinkStatus: .live(bpm: 142)
    )
    .padding()
    .helmTheme()
}

#Preview("Train session header connecting watch") {
    TrainSessionHeaderView(
        startedAt: Date().addingTimeInterval(-30),
        progress: TrainSessionProgress(elapsedSeconds: 30, completedSetCount: 0, totalSetCount: 5),
        watchLinkStatus: .connecting(.watch)
    )
    .padding()
    .helmTheme()
}

#Preview("Train session header connecting phone") {
    TrainSessionHeaderView(
        startedAt: Date().addingTimeInterval(-30),
        progress: TrainSessionProgress(elapsedSeconds: 30, completedSetCount: 0, totalSetCount: 5),
        watchLinkStatus: .connecting(.phone)
    )
    .padding()
    .helmTheme()
}
