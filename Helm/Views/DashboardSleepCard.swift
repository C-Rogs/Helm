import Core
import DesignSystem
import SwiftUI

struct DashboardSleepCard: View {
    let summary: SleepNightSummary
    var showsChevron = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                HStack {
                    HelmSectionEyebrow("SLEEP")
                    Spacer()
                    if showsChevron {
                        HelmIconView(.chevronRight, context: .inline)
                            .foregroundStyle(HelmColor.fgMuted)
                    }
                }

                if let asleepHours = summary.asleepHours {
                    Text(SleepDurationFormatting.hoursAndMinutes(from: asleepHours))
                        .helmType(.heroNumber)
                        .accessibilityLabel("Time asleep \(SleepDurationFormatting.hoursAndMinutes(from: asleepHours))")

                    if let secondary = secondaryLine {
                        Text(secondary)
                            .helmType(.body, color: HelmColor.fgSecondary)
                    }
                } else {
                    Text("No sleep data")
                        .helmType(.body, color: HelmColor.fgMuted)
                }
            }
        }
    }

    private var secondaryLine: String? {
        if let awakeMinutes = summary.awakeMinutes, awakeMinutes >= 1 {
            let awakeLabel = SleepDurationFormatting.hoursAndMinutes(from: awakeMinutes / 60.0)
            return "\(awakeLabel) awake"
        }
        if let efficiency = summary.efficiency {
            let percent = Int((efficiency * 100).rounded())
            return "\(percent)% efficiency"
        }
        return nil
    }
}

#Preview("Dashboard sleep card") {
    DashboardSleepCard(
        summary: SleepNightSummary(
            asleepHours: 5.55,
            awakeMinutes: 38,
            efficiency: 0.9
        )
    )
    .helmScreenPadding()
    .helmTheme()
}
