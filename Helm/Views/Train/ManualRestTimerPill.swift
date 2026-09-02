import DesignSystem
import SwiftUI

struct ManualRestTimerPill: View {
    let isRunning: Bool
    let endsAt: Date?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Group {
                if isRunning, let endsAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = max(0, Int(endsAt.timeIntervalSince(context.date).rounded(.down)))
                        pillLabel(seconds: remaining, emphasized: true)
                            .accessibilityValue(RestTimerFormatting.mmss(remaining))
                    }
                    .fixedSize()
                } else {
                    pillLabel(seconds: nil, emphasized: false)
                }
            }
        }
        .buttonStyle(.helmPressable)
        .accessibilityLabel(isRunning ? "Rest timer" : "Open manual rest timer")
        .accessibilityHint(isRunning ? "Opens timer controls" : "Opens manual rest timer")
    }

    @ViewBuilder
    private func pillLabel(seconds: Int?, emphasized: Bool) -> some View {
        HStack(spacing: HelmSpacing.xxs) {
            Image(systemName: "timer")
                .font(.body.weight(.semibold))
                .foregroundStyle(emphasized ? HelmColor.accent : HelmColor.fg)

            if let seconds {
                Text(RestTimerFormatting.mmss(seconds))
                    .helmType(.label, color: HelmColor.fg)
                    .helmNumericRoll(value: seconds)
                    .lineLimit(1)
            } else {
                Text("Rest Timer")
                    .helmType(.label, color: HelmColor.fg)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, HelmSpacing.sm)
        .frame(minHeight: 44)
        .background(
            emphasized ? HelmColor.accent.opacity(0.12) : HelmColor.surfaceElevated,
            in: Capsule()
        )
        .overlay {
            Capsule()
                .strokeBorder(
                    emphasized ? HelmColor.accent.opacity(0.35) : HelmColor.hairline,
                    lineWidth: 1
                )
        }
    }
}

#Preview("Manual rest timer pill idle") {
    ManualRestTimerPill(isRunning: false, endsAt: nil) {}
        .padding()
        .helmTheme()
}

#Preview("Manual rest timer pill running") {
    ManualRestTimerPill(isRunning: true, endsAt: Date().addingTimeInterval(83)) {}
        .padding()
        .helmTheme()
}
